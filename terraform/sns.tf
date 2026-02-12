# -----------------------------------------------------
# SNS Topic — call notifications
# -----------------------------------------------------

resource "aws_sns_topic" "call_notifications" {
  name         = "${var.project_name}-notifications"
  display_name = "Caller Agent Notifications"

  tags = {
    Project = var.project_name
  }
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.call_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}
