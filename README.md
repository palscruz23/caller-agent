# Caller Answering Agent

An automated phone answering agent built on AWS that answers calls on your behalf when you're unavailable. It uses Claude (via Amazon Bedrock) to have natural conversations with callers, collects their information, detects spam calls, and notifies you via email.

## Architecture

```
Incoming Call → Amazon Connect → Amazon Lex V2 (ASR/TTS)
                                       ↓
                              Bedrock Agent (Claude 3.5 Sonnet)
                                       ↓
                              Lambda (Action Group)
                             ┌─────┬───────┬──────┐
                             │     │       │      │
                          Spam  Caller   Save   Send
                          Check  Info   Record  Notification
                        (NumVerify)    (DynamoDB) (SNS → Email)
```

## What It Does

- Answers incoming phone calls with a professional greeting
- Collects the caller's **name**, **phone number**, and **reason for calling**
- Optionally checks the phone number for spam using the NumVerify API
- Blocks spam callers politely
- Saves legitimate call records to DynamoDB
- Sends you an email notification with the caller's details
- Runs 24/7 via Amazon Connect

## Prerequisites

1. **AWS Account** with CLI configured (`aws configure`)
2. **Terraform** >= 1.5.0
3. **Python 3.13+** with `pip` (for Lambda dependency bundling)
4. **PowerShell** (used by Terraform's local-exec provisioner for Lambda builds on Windows)

## Setup

### 1. Enable Bedrock model access

The Bedrock Agent uses **Claude 3.5 Sonnet v2** (`anthropic.claude-3-5-sonnet-20241022-v2:0`). You must enable access to this model:

1. Open the [Amazon Bedrock console](https://console.aws.amazon.com/bedrock/) in your target region
2. Go to **Model access** and request access to **Anthropic Claude 3.5 Sonnet v2**
3. Your IAM user/role may need `aws-marketplace:ViewSubscriptions` and `aws-marketplace:Subscribe` permissions to enable the model

### 2. Configure deployment settings

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
aws_region             = "ap-southeast-2"
notification_email     = "your-email@example.com"
connect_instance_alias = "caller-agent"       # must be globally unique
connect_phone_country  = "AU"                  # country for phone number
connect_phone_type     = "DID"                 # DID or TOLL_FREE

# Optional: spam detection via NumVerify API
enable_spam_detection  = false
# numverify_secret_name = "caller-agent/numverify-api-key"
```

### 3. (Optional) Store NumVerify API key

If you enabled spam detection, create the secret in AWS Secrets Manager:

```bash
aws secretsmanager create-secret \
  --name caller-agent/numverify-api-key \
  --secret-string '{"api_key": "YOUR_NUMVERIFY_API_KEY"}'
```

### 4. Deploy with Terraform

```bash
cd terraform
terraform init
terraform apply
```

This creates all AWS resources: Connect instance, phone number, Lex V2 bot, Bedrock Agent, Lambda, DynamoDB table, and SNS topic.

### 5. Confirm SNS subscription

Check your email inbox and confirm the SNS subscription to start receiving call notifications.

### 6. Create the Lex BedrockAgentIntent (manual step)

The `AMAZON.BedrockAgentIntent` intent type is not supported by Terraform or the AWS CLI. You must create it manually:

1. Open the [Amazon Lex V2 console](https://console.aws.amazon.com/lexv2/)
2. Select the **CallerAnsweringBot** bot
3. Go to **Intents** under the **en_AU** locale
4. Click **Add intent** → **Built-in intent** → select **AMAZON.BedrockAgentIntent**
5. Under **Bedrock Agent**, select the **caller-answering-agent** and the **live** alias
6. Save the intent and **Build** the bot
7. After building, run `terraform apply` again to create a new bot version pointing to the updated DRAFT

### 7. Test

Call the phone number shown in the Terraform output (`phone_number`). The bot should greet you, collect your information, and send you an email notification.

## Project Structure

```
caller-agent/
├── terraform/
│   ├── main.tf                     # Provider config, data sources
│   ├── variables.tf                # Input variables
│   ├── outputs.tf                  # Output values (phone number, IDs, ARNs)
│   ├── connect.tf                  # Connect instance, hours, queue, phone, flow
│   ├── lex.tf                      # Lex V2 bot, locale, version, alias
│   ├── bedrock.tf                  # Bedrock Agent, action group, alias
│   ├── lambda.tf                   # Lambda function, IAM, build pipeline
│   ├── terraform.tfvars.example    # Example variable values
│   └── build/                      # Generated: Lambda build artifacts
├── lambda_functions/
│   └── agent_action_handler/
│       ├── index.py                # Lambda: spam check, save record, notify
│       └── requirements.txt        # Python dependencies
├── schemas/
│   └── openapi_schema.json         # Bedrock Agent action group API schema
└── config/
    ├── agent_instructions.txt      # Bedrock Agent system prompt
    └── contact_flow.json           # Amazon Connect contact flow definition
```

## AWS Resources Created

| Resource | Service | Purpose |
|----------|---------|---------|
| Connect instance + phone number | Amazon Connect | Receives incoming phone calls |
| 24/7 hours of operation + queue | Amazon Connect | Call routing configuration |
| Caller Agent Flow | Amazon Connect | Contact flow with Lex bot integration |
| CallerAnsweringBot | Lex V2 | Speech-to-text / text-to-speech (en_AU, Olivia neural voice) |
| caller-answering-agent | Bedrock Agent | Claude-powered conversation handler |
| caller-agent-action-handler | Lambda | Bedrock Agent tool execution (spam check, save, notify) |
| caller-agent-call-records | DynamoDB | Stores call records |
| caller-agent-notifications | SNS | Email notifications to phone owner |

## Key Configuration

- **Contact flow** (`config/contact_flow.json`): Sets language to `en-AU`, voice to Olivia (neural), and routes the call through the Lex bot. The `${LEX_BOT_ALIAS_ARN}` placeholder is replaced by Terraform at deploy time.
- **Agent instructions** (`config/agent_instructions.txt`): Controls the AI agent's behavior — greeting style, information collection, spam handling, and conversation flow.
- **OpenAPI schema** (`schemas/openapi_schema.json`): Defines the tools available to the Bedrock Agent (checkSpam, saveCallRecord, sendNotification).

## Notes

- The Lex bot uses the **en_AU** locale. The contact flow must set the language attribute to `en-AU` before invoking the Lex bot, otherwise Connect returns a `BadRequestException`.
- After the conversation completes (or 60 seconds of silence), the call ends with a "Goodbye" message.
- The Lambda build step uses PowerShell (`local-exec` provisioner). On non-Windows systems, update `terraform/lambda.tf` to use bash commands instead.

## License

MIT
