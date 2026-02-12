#!/usr/bin/env python3
import aws_cdk as cdk

from stacks.caller_agent_stack import CallerAgentStack

app = cdk.App()

CallerAgentStack(
    app,
    "CallerAgentStack",
    env=cdk.Environment(
        region=app.node.try_get_context("aws_region") or "us-east-1",
    ),
    description="Automated caller answering agent with Bedrock, Connect, and Lex",
)

app.synth()
