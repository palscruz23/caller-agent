# -----------------------------------------------------
# Amazon Connect — integration + contact flow
# (Only created if connect_instance_arn is provided)
# -----------------------------------------------------

locals {
  create_connect = var.connect_instance_arn != ""

  # Extract instance ID from ARN for resources that need it
  # ARN format: arn:aws:connect:region:account:instance/instance-id
  connect_instance_id = local.create_connect ? regex("instance/(.+)$", var.connect_instance_arn)[0] : ""

  lex_bot_alias_arn = "arn:aws:lex:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:bot-alias/${aws_lexv2models_bot.caller_bot.id}/${aws_lexv2models_bot_alias.live.id}"
}

# Associate Lex bot with Connect instance
resource "aws_connect_bot_association" "lex_bot" {
  count       = local.create_connect ? 1 : 0
  instance_id = var.connect_instance_arn

  lex_bot {
    lex_region = data.aws_region.current.name
    name       = aws_lexv2models_bot.caller_bot.name

    lex_v2_bot {
      alias_arn = local.lex_bot_alias_arn
    }
  }
}

# Contact Flow
resource "aws_connect_contact_flow" "caller_agent" {
  count       = local.create_connect ? 1 : 0
  instance_id = var.connect_instance_arn
  name        = "Caller Agent Flow"
  type        = "CONTACT_FLOW"
  description = "Automated caller answering agent flow"

  content = replace(
    file("${path.module}/../config/contact_flow.json"),
    "$${LEX_BOT_ALIAS_ARN}",
    local.lex_bot_alias_arn
  )

  depends_on = [aws_connect_bot_association.lex_bot]
}
