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
          "${aws_bedrockagent_agent.caller_agent.agent_arn}/*"
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

# Bot Locale — en_US with Joanna neural voice
resource "aws_lexv2models_bot_locale" "en_us" {
  bot_id                           = aws_lexv2models_bot.caller_bot.id
  bot_version                      = "DRAFT"
  locale_id                        = "en_US"
  n_lu_intent_confidence_threshold = 0.40

  voice_settings {
    voice_id = "Joanna"
    engine   = "neural"
  }
}

# Primary Intent — delegates to Bedrock Agent (QnA intent)
resource "aws_lexv2models_intent" "bedrock_agent_handler" {
  bot_id      = aws_lexv2models_bot.caller_bot.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  name        = "BedrockAgentHandler"
  description = "Delegates conversation to Bedrock Agent for intelligent call handling"

  parent_intent_signature = "AMAZON.QnAIntent"

  sample_utterance {
    utterance = "I would like to leave a message"
  }
  sample_utterance {
    utterance = "I'm calling about"
  }
  sample_utterance {
    utterance = "My name is"
  }
  sample_utterance {
    utterance = "I need to speak with someone"
  }
  sample_utterance {
    utterance = "Hello"
  }
  sample_utterance {
    utterance = "Hi"
  }
  sample_utterance {
    utterance = "I have a question"
  }
}

# Required Fallback Intent
resource "aws_lexv2models_intent" "fallback" {
  bot_id      = aws_lexv2models_bot.caller_bot.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  name        = "FallbackIntent"
  description = "Default fallback intent"

  parent_intent_signature = "AMAZON.FallbackIntent"

  closing_setting {
    active = true

    closing_response {
      message_group {
        message {
          plain_text_message {
            value = "I'm sorry, I didn't understand. Let me connect you with someone who can help. Goodbye."
          }
        }
      }
    }
  }
}

# Bot Version — created from DRAFT after intents are defined
resource "aws_lexv2models_bot_version" "v1" {
  bot_id = aws_lexv2models_bot.caller_bot.id

  locale_specification = {
    "en_US" = {
      source_bot_version = "DRAFT"
    }
  }

  depends_on = [
    aws_lexv2models_intent.bedrock_agent_handler,
    aws_lexv2models_intent.fallback,
  ]
}

# Bot Alias — "live" pointing to the version
resource "aws_lexv2models_bot_alias" "live" {
  bot_id       = aws_lexv2models_bot.caller_bot.id
  bot_version  = aws_lexv2models_bot_version.v1.bot_version
  bot_alias_name = "live"

  bot_alias_locale_setting {
    locale_id = "en_US"
    bot_alias_locale_setting {
      enabled = true
    }
  }

  tags = {
    Project = var.project_name
  }
}
