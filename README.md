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
- Checks the phone number for spam using the NumVerify API
- Blocks spam callers politely
- Saves legitimate call records to DynamoDB
- Sends you an email notification with the caller's details
- Runs 24/7 via Amazon Connect

## Prerequisites

1. **AWS Account** with Bedrock Claude model access enabled
2. **Amazon Connect instance** — create one in the AWS Console and claim a phone number
3. **NumVerify API key** — sign up at [numverify.com](https://numverify.com) (free tier: 100 requests/month)
4. **Docker Desktop** — required for CDK Lambda bundling on Windows
5. **AWS CDK CLI** — `npm install -g aws-cdk`
6. **Python 3.13+**

## Setup

### 1. Install dependencies

```bash
pip install -e .
```

### 2. Store your NumVerify API key in Secrets Manager

```bash
aws secretsmanager create-secret \
  --name caller-agent/numverify-api-key \
  --secret-string '{"api_key": "YOUR_NUMVERIFY_API_KEY"}'
```

### 3. Configure deployment settings

Edit `cdk.json` and fill in the context values:

```json
{
  "context": {
    "connect_instance_arn": "arn:aws:connect:us-east-1:123456789012:instance/your-instance-id",
    "notification_email": "your-email@example.com",
    "aws_region": "us-east-1"
  }
}
```

### 4. Deploy

```bash
cdk bootstrap   # first time only
cdk deploy
```

### 5. Confirm SNS subscription

Check your email inbox and confirm the SNS subscription to start receiving call notifications.

### 6. Assign the contact flow

In the Amazon Connect console, assign the **"Caller Agent Flow"** contact flow to your claimed phone number.

## Project Structure

```
caller-agent/
├── app.py                          # CDK app entry point
├── cdk.json                        # CDK config + deployment settings
├── pyproject.toml                  # Python project config
├── stacks/
│   └── caller_agent_stack.py       # CDK stack (all AWS resources)
├── lambda_functions/
│   └── agent_action_handler/
│       ├── index.py                # Lambda: spam check, save record, notify
│       └── requirements.txt
├── schemas/
│   └── openapi_schema.json         # Bedrock Agent action group API schema
└── config/
    ├── agent_instructions.txt      # Bedrock Agent system prompt
    └── contact_flow.json           # Amazon Connect contact flow
```

## AWS Resources Created

| Resource | Service | Purpose |
|----------|---------|---------|
| `caller-agent-call-records` | DynamoDB | Stores call records |
| `caller-agent-notifications` | SNS | Email notifications |
| `caller-agent-action-handler` | Lambda | Bedrock Agent tool execution |
| `caller-answering-agent` | Bedrock Agent | Claude-powered conversation |
| `CallerAnsweringBot` | Lex V2 | Speech-to-text / text-to-speech |
| `Caller Agent Flow` | Connect | Phone call routing |

## License

MIT
