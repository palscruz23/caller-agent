# -----------------------------------------------------
# Outputs
# -----------------------------------------------------

output "dynamodb_table_name" {
  description = "Name of the DynamoDB call records table"
  value       = aws_dynamodb_table.call_records.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS notification topic"
  value       = aws_sns_topic.call_notifications.arn
}

output "lambda_function_arn" {
  description = "ARN of the Lambda action handler"
  value       = aws_lambda_function.agent_action_handler.arn
}

output "bedrock_agent_id" {
  description = "ID of the Bedrock Agent"
  value       = aws_bedrockagent_agent.caller_agent.agent_id
}

output "bedrock_agent_alias_id" {
  description = "ID of the Bedrock Agent alias"
  value       = aws_bedrockagent_agent_alias.live.agent_alias_id
}

output "lex_bot_id" {
  description = "ID of the Lex V2 Bot"
  value       = aws_lexv2models_bot.caller_bot.id
}

output "lex_bot_alias_id" {
  description = "ID of the Lex Bot alias"
  value       = awscc_lex_bot_alias.live.bot_alias_id
}

output "connect_instance_id" {
  description = "ID of the Amazon Connect instance"
  value       = aws_connect_instance.this.id
}

output "connect_instance_arn" {
  description = "ARN of the Amazon Connect instance"
  value       = aws_connect_instance.this.arn
}

output "contact_flow_arn" {
  description = "ARN of the Connect contact flow"
  value       = aws_connect_contact_flow.caller_agent.arn
}

output "phone_number" {
  description = "The claimed phone number for incoming calls"
  value       = aws_connect_phone_number.caller_agent.phone_number
}
