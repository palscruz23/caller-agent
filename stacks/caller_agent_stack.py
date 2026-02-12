"""CDK Stack for the Caller Answering Agent.

Creates all AWS resources: DynamoDB, SNS, Lambda, Bedrock Agent,
Lex V2 Bot, and Amazon Connect integration.
"""

import json
import os
from pathlib import Path

from aws_cdk import (
    CfnOutput,
    Duration,
    RemovalPolicy,
    Stack,
    aws_dynamodb as dynamodb,
    aws_iam as iam,
    aws_lambda as _lambda,
    aws_secretsmanager as secretsmanager,
    aws_sns as sns,
    aws_sns_subscriptions as subs,
    aws_bedrock as bedrock,
    aws_lex as lex,
    aws_connect as connect,
)
from constructs import Construct

PROJECT_ROOT = Path(__file__).parent.parent


class CallerAgentStack(Stack):
    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # -------------------------------------------------------
        # 1. DynamoDB Table — stores call records
        # -------------------------------------------------------
        call_records_table = dynamodb.Table(
            self,
            "CallRecordsTable",
            table_name="caller-agent-call-records",
            partition_key=dynamodb.Attribute(
                name="call_id",
                type=dynamodb.AttributeType.STRING,
            ),
            sort_key=dynamodb.Attribute(
                name="timestamp",
                type=dynamodb.AttributeType.STRING,
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
        )

        call_records_table.add_global_secondary_index(
            index_name="phone-number-index",
            partition_key=dynamodb.Attribute(
                name="caller_phone",
                type=dynamodb.AttributeType.STRING,
            ),
            sort_key=dynamodb.Attribute(
                name="timestamp",
                type=dynamodb.AttributeType.STRING,
            ),
        )

        # -------------------------------------------------------
        # 2. SNS Topic — call notifications
        # -------------------------------------------------------
        notification_topic = sns.Topic(
            self,
            "CallNotificationTopic",
            topic_name="caller-agent-notifications",
            display_name="Caller Agent Notifications",
        )

        notification_email = self.node.try_get_context("notification_email")
        if notification_email:
            notification_topic.add_subscription(
                subs.EmailSubscription(notification_email)
            )

        # -------------------------------------------------------
        # 3. Secrets Manager — NumVerify API key reference
        # -------------------------------------------------------
        numverify_secret = secretsmanager.Secret.from_secret_name_v2(
            self,
            "NumVerifyApiKey",
            secret_name=self.node.try_get_context("numverify_api_key_secret_name")
            or "caller-agent/numverify-api-key",
        )

        # -------------------------------------------------------
        # 4. Lambda Function — Bedrock Agent action group handler
        # -------------------------------------------------------
        agent_action_handler = _lambda.Function(
            self,
            "AgentActionHandler",
            function_name="caller-agent-action-handler",
            runtime=_lambda.Runtime.PYTHON_3_13,
            handler="index.lambda_handler",
            code=_lambda.Code.from_asset(
                str(PROJECT_ROOT / "lambda_functions" / "agent_action_handler"),
                bundling=_lambda.BundlingOptions(
                    image=_lambda.Runtime.PYTHON_3_13.bundling_image,
                    command=[
                        "bash",
                        "-c",
                        "pip install -r requirements.txt -t /asset-output && "
                        "cp -au . /asset-output",
                    ],
                ),
            ),
            timeout=Duration.seconds(30),
            memory_size=256,
            environment={
                "CALL_RECORDS_TABLE": call_records_table.table_name,
                "NOTIFICATION_TOPIC_ARN": notification_topic.topic_arn,
                "NUMVERIFY_SECRET_NAME": numverify_secret.secret_name,
            },
        )

        call_records_table.grant_read_write_data(agent_action_handler)
        notification_topic.grant_publish(agent_action_handler)
        numverify_secret.grant_read(agent_action_handler)

        # -------------------------------------------------------
        # 5. Bedrock Agent IAM Role
        # -------------------------------------------------------
        bedrock_agent_role = iam.Role(
            self,
            "BedrockAgentRole",
            role_name=f"caller-agent-bedrock-role-{self.region}",
            assumed_by=iam.ServicePrincipal("bedrock.amazonaws.com"),
            inline_policies={
                "BedrockInvokeModel": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            actions=["bedrock:InvokeModel"],
                            resources=[
                                f"arn:aws:bedrock:{self.region}::foundation-model/"
                                "anthropic.claude-3-5-sonnet-20241022-v2:0",
                            ],
                        ),
                    ]
                ),
            },
        )

        # -------------------------------------------------------
        # 6. Bedrock Agent — Claude-powered conversation handler
        # -------------------------------------------------------
        agent_instructions = (
            PROJECT_ROOT / "config" / "agent_instructions.txt"
        ).read_text(encoding="utf-8")

        openapi_schema = (
            PROJECT_ROOT / "schemas" / "openapi_schema.json"
        ).read_text(encoding="utf-8")

        caller_agent = bedrock.CfnAgent(
            self,
            "CallerAgent",
            agent_name="caller-answering-agent",
            agent_resource_role_arn=bedrock_agent_role.role_arn,
            foundation_model="anthropic.claude-3-5-sonnet-20241022-v2:0",
            instruction=agent_instructions,
            idle_session_ttl_in_seconds=600,
            auto_prepare=True,
            description=(
                "Automated caller answering agent that greets callers, "
                "collects information, checks for spam, and notifies the owner."
            ),
            action_groups=[
                bedrock.CfnAgent.AgentActionGroupProperty(
                    action_group_name="CallerManagementActions",
                    action_group_executor=bedrock.CfnAgent.ActionGroupExecutorProperty(
                        lambda_=agent_action_handler.function_arn,
                    ),
                    api_schema=bedrock.CfnAgent.APISchemaProperty(
                        payload=openapi_schema,
                    ),
                    action_group_state="ENABLED",
                    description=(
                        "Actions for managing incoming calls: spam detection, "
                        "saving records, sending notifications, and phone lookups."
                    ),
                ),
            ],
        )

        # Grant Bedrock permission to invoke the Lambda
        agent_action_handler.add_permission(
            "AllowBedrockInvocation",
            principal=iam.ServicePrincipal("bedrock.amazonaws.com"),
            source_arn=caller_agent.attr_agent_arn,
        )

        # -------------------------------------------------------
        # 7. Bedrock Agent Alias — required for Lex integration
        # -------------------------------------------------------
        agent_alias = bedrock.CfnAgentAlias(
            self,
            "CallerAgentAlias",
            agent_id=caller_agent.attr_agent_id,
            agent_alias_name="live",
            description="Production alias for the caller answering agent",
        )
        agent_alias.add_dependency(caller_agent)

        # -------------------------------------------------------
        # 8. Lex Bot IAM Role
        # -------------------------------------------------------
        lex_bot_role = iam.Role(
            self,
            "LexBotRole",
            role_name=f"caller-agent-lex-role-{self.region}",
            assumed_by=iam.ServicePrincipal("lexv2.amazonaws.com"),
            inline_policies={
                "LexBedrockAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            actions=[
                                "bedrock:InvokeAgent",
                                "bedrock:GetAgent",
                                "bedrock:GetAgentAlias",
                            ],
                            resources=[
                                caller_agent.attr_agent_arn,
                                f"{caller_agent.attr_agent_arn}/*",
                            ],
                        ),
                        iam.PolicyStatement(
                            actions=["polly:SynthesizeSpeech"],
                            resources=["*"],
                        ),
                    ]
                ),
            },
        )

        # -------------------------------------------------------
        # 9. Lex V2 Bot — speech interface with Bedrock Agent
        # -------------------------------------------------------
        caller_lex_bot = lex.CfnBot(
            self,
            "CallerLexBot",
            name="CallerAnsweringBot",
            role_arn=lex_bot_role.role_arn,
            data_privacy=lex.CfnBot.DataPrivacyProperty(
                child_directed=False,
            ),
            idle_session_ttl_in_seconds=300,
            description=(
                "Lex bot for automated caller answering "
                "with Bedrock Agent integration"
            ),
            bot_locales=[
                lex.CfnBot.BotLocaleProperty(
                    locale_id="en_US",
                    nlu_confidence_threshold=0.40,
                    voice_settings=lex.CfnBot.VoiceSettingsProperty(
                        voice_id="Joanna",
                        engine="neural",
                    ),
                    intents=[
                        # Primary intent — delegates to Bedrock Agent
                        lex.CfnBot.IntentProperty(
                            name="BedrockAgentHandler",
                            parent_intent_signature="AMAZON.QnAIntent",
                            description=(
                                "Delegates conversation to Bedrock Agent "
                                "for intelligent call handling"
                            ),
                            # QnA intent with Bedrock agent configuration
                            # is set up via the bedrock_knowledge_store_configuration
                            # or via post-deployment API call
                            sample_utterances=[
                                lex.CfnBot.SampleUtteranceProperty(
                                    utterance="I would like to leave a message"
                                ),
                                lex.CfnBot.SampleUtteranceProperty(
                                    utterance="I'm calling about"
                                ),
                                lex.CfnBot.SampleUtteranceProperty(
                                    utterance="My name is"
                                ),
                                lex.CfnBot.SampleUtteranceProperty(
                                    utterance="I need to speak with someone"
                                ),
                                lex.CfnBot.SampleUtteranceProperty(
                                    utterance="Hello"
                                ),
                                lex.CfnBot.SampleUtteranceProperty(
                                    utterance="Hi"
                                ),
                                lex.CfnBot.SampleUtteranceProperty(
                                    utterance="I have a question"
                                ),
                            ],
                        ),
                        # Required fallback intent
                        lex.CfnBot.IntentProperty(
                            name="FallbackIntent",
                            description="Default fallback intent",
                            parent_intent_signature="AMAZON.FallbackIntent",
                            intent_closing_setting=lex.CfnBot.IntentClosingSettingProperty(
                                closing_response=lex.CfnBot.ResponseSpecificationProperty(
                                    message_groups_list=[
                                        lex.CfnBot.MessageGroupProperty(
                                            message=lex.CfnBot.MessageProperty(
                                                plain_text_message=lex.CfnBot.PlainTextMessageProperty(
                                                    value=(
                                                        "I'm sorry, I didn't understand. "
                                                        "Let me connect you with someone "
                                                        "who can help. Goodbye."
                                                    ),
                                                ),
                                            ),
                                        ),
                                    ],
                                ),
                            ),
                        ),
                    ],
                ),
            ],
            auto_build_bot_locales=True,
        )

        # -------------------------------------------------------
        # 10. Lex Bot Version + Alias — required for Connect
        # -------------------------------------------------------
        bot_version = lex.CfnBotVersion(
            self,
            "CallerLexBotVersion",
            bot_id=caller_lex_bot.attr_id,
            bot_version_locale_specification=[
                lex.CfnBotVersion.BotVersionLocaleSpecificationProperty(
                    bot_version_locale_details=lex.CfnBotVersion.BotVersionLocaleDetailsProperty(
                        source_bot_version="DRAFT",
                    ),
                    locale_id="en_US",
                ),
            ],
        )
        bot_version.add_dependency(caller_lex_bot)

        bot_alias = lex.CfnBotAlias(
            self,
            "CallerLexBotAlias",
            bot_alias_name="live",
            bot_id=caller_lex_bot.attr_id,
            bot_version=bot_version.attr_bot_version,
            bot_alias_locale_settings=[
                lex.CfnBotAlias.BotAliasLocaleSettingsMapProperty(
                    bot_alias_locale_setting=lex.CfnBotAlias.BotAliasLocaleSettingsProperty(
                        enabled=True,
                    ),
                    locale_id="en_US",
                ),
            ],
        )
        bot_alias.add_dependency(bot_version)

        # -------------------------------------------------------
        # 11. Amazon Connect Integration — Lex bot association
        # -------------------------------------------------------
        connect_instance_arn = self.node.try_get_context("connect_instance_arn")

        if connect_instance_arn:
            lex_bot_alias_arn = (
                f"arn:aws:lex:{self.region}:{self.account}:bot-alias/"
                f"{caller_lex_bot.attr_id}/{bot_alias.attr_bot_alias_id}"
            )

            lex_integration = connect.CfnIntegrationAssociation(
                self,
                "LexBotIntegration",
                instance_id=connect_instance_arn,
                integration_arn=lex_bot_alias_arn,
                integration_type="LEX_BOT",
            )

            # -------------------------------------------------------
            # 12. Amazon Connect Contact Flow
            # -------------------------------------------------------
            contact_flow_content = (
                PROJECT_ROOT / "config" / "contact_flow.json"
            ).read_text(encoding="utf-8")

            # Replace placeholder with actual Lex bot alias ARN
            contact_flow_content = contact_flow_content.replace(
                "${LEX_BOT_ALIAS_ARN}", lex_bot_alias_arn
            )

            contact_flow = connect.CfnContactFlow(
                self,
                "CallerAgentContactFlow",
                instance_arn=connect_instance_arn,
                name="Caller Agent Flow",
                type="CONTACT_FLOW",
                description="Automated caller answering agent flow",
                content=contact_flow_content,
            )
            contact_flow.add_dependency(lex_integration)

            CfnOutput(
                self,
                "ContactFlowArn",
                value=contact_flow.attr_contact_flow_arn,
            )

        # -------------------------------------------------------
        # Outputs
        # -------------------------------------------------------
        CfnOutput(self, "DynamoDBTableName", value=call_records_table.table_name)
        CfnOutput(self, "SNSTopicArn", value=notification_topic.topic_arn)
        CfnOutput(self, "LambdaFunctionArn", value=agent_action_handler.function_arn)
        CfnOutput(self, "BedrockAgentId", value=caller_agent.attr_agent_id)
        CfnOutput(
            self,
            "BedrockAgentAliasId",
            value=agent_alias.attr_agent_alias_id,
        )
        CfnOutput(self, "LexBotId", value=caller_lex_bot.attr_id)
        CfnOutput(self, "LexBotAliasId", value=bot_alias.attr_bot_alias_id)
