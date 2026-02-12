variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used as prefix for resource naming"
  type        = string
  default     = "caller-agent"
}

variable "connect_instance_arn" {
  description = "ARN of an existing Amazon Connect instance. Leave empty to skip Connect resources."
  type        = string
  default     = ""
}

variable "notification_email" {
  description = "Email address to receive SNS call notifications. Leave empty to skip subscription."
  type        = string
  default     = ""
}

variable "numverify_secret_name" {
  description = "Name of the Secrets Manager secret containing the NumVerify API key"
  type        = string
  default     = "caller-agent/numverify-api-key"
}
