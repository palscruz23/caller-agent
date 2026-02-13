# -----------------------------------------------------
# Lex V2 Bot — speech interface with Bedrock Agent
# -----------------------------------------------------

# IAM Role for Lex Bot
resource "aws_iam_role" "lex_bot" {
  name = "${var.project_name}-lex-role-${var.aws_region}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lexv2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Project = var.project_name
  }
}

resource "aws_iam_role_policy" "lex_bot_permissions" {
  name = "${var.project_name}-lex-policy"
  role = aws_iam_role.lex_bot.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockAgentAccess"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeAgent",
          "bedrock:GetAgent",
          "bedrock:GetAgentAlias"
        ]
        Resource = [
          aws_bedrockagent_agent.caller_agent.agent_arn,
          "${aws_bedrockagent_agent.caller_agent.agent_arn}/*",
          "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:agent-alias/${aws_bedrockagent_agent.caller_agent.agent_id}/*"
        ]
      },
      {
        Sid      = "PollySynthesizeSpeech"
        Effect   = "Allow"
        Action   = ["polly:SynthesizeSpeech"]
        Resource = "*"
      }
    ]
  })
}

# Lex V2 Bot
resource "aws_lexv2models_bot" "caller_bot" {
  name        = "CallerAnsweringBot"
  description = "Lex bot for automated caller answering with Bedrock Agent integration"
  role_arn    = aws_iam_role.lex_bot.arn

  idle_session_ttl_in_seconds = 300

  data_privacy {
    child_directed = false
  }

  tags = {
    Project = var.project_name
  }
}

# Bot Locale — en_AU with Olivia neural voice
resource "aws_lexv2models_bot_locale" "en_au" {
  bot_id                           = aws_lexv2models_bot.caller_bot.id
  bot_version                      = "DRAFT"
  locale_id                        = "en_AU"
  n_lu_intent_confidence_threshold = 0.40

  voice_settings {
    voice_id = "Olivia"
    engine   = "neural"
  }
}

# Primary Intent (BedrockAgentHandler) is created manually via the AWS Console
# because neither the Terraform provider nor the AWS CLI support AMAZON.BedrockAgentIntent.

# Bot Version — created from DRAFT after intents are defined
resource "aws_lexv2models_bot_version" "v1" {
  bot_id = aws_lexv2models_bot.caller_bot.id

  locale_specification = {
    "en_AU" = {
      source_bot_version = "DRAFT"
    }
  }

  depends_on = [
    aws_lexv2models_bot_locale.en_au,
  ]
}

# Bot Alias — "live" pointing to the version
# Using awscc provider because aws_lexv2models_bot_alias does not exist in hashicorp/aws
resource "awscc_lex_bot_alias" "live" {
  bot_alias_name = "live"
  bot_id         = aws_lexv2models_bot.caller_bot.id
  bot_version    = aws_lexv2models_bot_version.v1.bot_version
  description    = "Live alias for caller answering bot"

  bot_alias_locale_settings = [
    {
      locale_id = "en_AU"
      bot_alias_locale_setting = {
        enabled = true
      }
    }
  ]

  bot_alias_tags = [
    {
      key   = "Project"
      value = var.project_name
    }
  ]
}
