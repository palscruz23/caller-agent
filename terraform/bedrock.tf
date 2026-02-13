# -----------------------------------------------------
# Bedrock Agent — Claude-powered conversation handler
# -----------------------------------------------------

# IAM Role for Bedrock Agent
resource "aws_iam_role" "bedrock_agent" {
  name = "${var.project_name}-bedrock-role-${var.aws_region}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Project = var.project_name
  }
}

resource "aws_iam_role_policy" "bedrock_agent_permissions" {
  name = "${var.project_name}-bedrock-policy"
  role = aws_iam_role.bedrock_agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeModel"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/anthropic.claude-3-5-sonnet-20241022-v2:0"
        ]
      }
    ]
  })
}

# Bedrock Agent
resource "aws_bedrockagent_agent" "caller_agent" {
  agent_name              = "caller-answering-agent"
  agent_resource_role_arn = aws_iam_role.bedrock_agent.arn
  foundation_model        = "anthropic.claude-3-5-sonnet-20241022-v2:0"
  instruction             = file("${path.module}/../config/agent_instructions.txt")
  idle_session_ttl_in_seconds = 600
  prepare_agent           = true
  description             = "Automated caller answering agent that greets callers, collects information, checks for spam, and notifies the owner."

  tags = {
    Project = var.project_name
  }
}

# Action Group — links the Lambda tools to the agent
resource "aws_bedrockagent_agent_action_group" "caller_management" {
  action_group_name          = "CallerManagementActions"
  agent_id                   = aws_bedrockagent_agent.caller_agent.agent_id
  agent_version              = "DRAFT"
  description                = "Actions for managing incoming calls: spam detection, saving records, sending notifications, and phone lookups."
  skip_resource_in_use_check = true

  action_group_executor {
    lambda = aws_lambda_function.agent_action_handler.arn
  }

  api_schema {
    payload = file("${path.module}/../schemas/openapi_schema.json")
  }
}

# Agent Alias — required for Lex integration
resource "aws_bedrockagent_agent_alias" "live" {
  agent_id         = aws_bedrockagent_agent.caller_agent.agent_id
  agent_alias_name = "live"
  description      = "Production alias for the caller answering agent"

  tags = {
    Project = var.project_name
  }

  depends_on = [aws_bedrockagent_agent_action_group.caller_management]
}
