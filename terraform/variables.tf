variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-southeast-2"
}

variable "project_name" {
  description = "Project name used as prefix for resource naming"
  type        = string
  default     = "caller-agent"
}

variable "connect_instance_alias" {
  description = "Alias for the Amazon Connect instance (must be globally unique, lowercase, no spaces)"
  type        = string
  default     = "caller-agent"
}

variable "connect_phone_country" {
  description = "Country code for claiming a Connect phone number (e.g., US, GB, AU)"
  type        = string
  default     = "AU"
}

variable "connect_phone_type" {
  description = "Type of phone number to claim: TOLL_FREE or DID"
  type        = string
  default     = "DID"
}

variable "notification_email" {
  description = "Email address to receive SNS call notifications"
  type        = string
}

variable "enable_spam_detection" {
  description = "Enable spam detection via NumVerify API. Requires a Secrets Manager secret with the API key."
  type        = bool
  default     = false
}

variable "numverify_secret_name" {
  description = "Name of the Secrets Manager secret containing the NumVerify API key (only used if enable_spam_detection = true)"
  type        = string
  default     = "caller-agent/numverify-api-key"
}
