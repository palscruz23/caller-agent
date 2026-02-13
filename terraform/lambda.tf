# -----------------------------------------------------
# Lambda — Bedrock Agent action group handler
# -----------------------------------------------------

locals {
  lambda_source_dir = "${path.module}/../lambda_functions/agent_action_handler"
  lambda_build_dir  = "${path.module}/build/lambda"
}

# Install Python dependencies into a build directory
resource "null_resource" "lambda_build" {
  triggers = {
    source_hash = filesha256("${local.lambda_source_dir}/index.py")
    deps_hash   = filesha256("${local.lambda_source_dir}/requirements.txt")
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command     = <<-EOT
      if (Test-Path "${local.lambda_build_dir}") { Remove-Item -Recurse -Force "${local.lambda_build_dir}" }
      New-Item -ItemType Directory -Force -Path "${local.lambda_build_dir}" | Out-Null
      Copy-Item "${local.lambda_source_dir}/index.py" "${local.lambda_build_dir}/"
      pip install -r "${local.lambda_source_dir}/requirements.txt" -t "${local.lambda_build_dir}" --quiet
    EOT
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = local.lambda_build_dir
  output_path = "${path.module}/build/lambda_payload.zip"

  depends_on = [null_resource.lambda_build]
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_execution" {
  name = "${var.project_name}-lambda-role-${var.aws_region}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Project = var.project_name
  }
}

resource "aws_iam_role_policy" "lambda_permissions" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "CloudWatchLogs"
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ]
          Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
        },
        {
          Sid    = "DynamoDBAccess"
          Effect = "Allow"
          Action = [
            "dynamodb:PutItem",
            "dynamodb:GetItem",
            "dynamodb:UpdateItem",
            "dynamodb:Query",
            "dynamodb:Scan"
          ]
          Resource = [
            aws_dynamodb_table.call_records.arn,
            "${aws_dynamodb_table.call_records.arn}/index/*"
          ]
        },
        {
          Sid    = "SNSPublish"
          Effect = "Allow"
          Action = [
            "sns:Publish"
          ]
          Resource = aws_sns_topic.call_notifications.arn
        },
      ],
      var.enable_spam_detection ? [
        {
          Sid    = "SecretsManagerRead"
          Effect = "Allow"
          Action = [
            "secretsmanager:GetSecretValue"
          ]
          Resource = data.aws_secretsmanager_secret.numverify[0].arn
        }
      ] : []
    )
  })
}

# Lambda Function
resource "aws_lambda_function" "agent_action_handler" {
  function_name    = "${var.project_name}-action-handler"
  role             = aws_iam_role.lambda_execution.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.13"
  timeout          = 30
  memory_size      = 256
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = merge(
      {
        CALL_RECORDS_TABLE     = aws_dynamodb_table.call_records.name
        NOTIFICATION_TOPIC_ARN = aws_sns_topic.call_notifications.arn
        SPAM_DETECTION_ENABLED = tostring(var.enable_spam_detection)
      },
      var.enable_spam_detection ? {
        NUMVERIFY_SECRET_NAME = var.numverify_secret_name
      } : {}
    )
  }

  tags = {
    Project = var.project_name
  }

  depends_on = [null_resource.lambda_build]
}

# Allow Bedrock to invoke the Lambda
resource "aws_lambda_permission" "allow_bedrock" {
  statement_id  = "AllowBedrockInvocation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.agent_action_handler.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagent_agent.caller_agent.agent_arn
}
