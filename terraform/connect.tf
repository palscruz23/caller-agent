# -----------------------------------------------------
# Amazon Connect — instance, hours, queue, phone, flow
# -----------------------------------------------------

locals {
  lex_bot_alias_arn = "arn:aws:lex:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:bot-alias/${aws_lexv2models_bot.caller_bot.id}/${awscc_lex_bot_alias.live.bot_alias_id}"
}

# 1. Connect Instance
resource "aws_connect_instance" "this" {
  identity_management_type = "CONNECT_MANAGED"
  instance_alias           = var.connect_instance_alias
  inbound_calls_enabled    = true
  outbound_calls_enabled   = false
  contact_flow_logs_enabled = true
}

# 2. Hours of Operation — 24/7
resource "aws_connect_hours_of_operation" "twenty_four_seven" {
  instance_id = aws_connect_instance.this.id
  name        = "24/7 Hours"
  description = "Available 24 hours a day, 7 days a week"
  time_zone   = "UTC"

  config {
    day = "MONDAY"
    start_time {
      hours   = 0
      minutes = 0
    }
    end_time {
      hours   = 23
      minutes = 59
    }
  }
  config {
    day = "TUESDAY"
    start_time {
      hours   = 0
      minutes = 0
    }
    end_time {
      hours   = 23
      minutes = 59
    }
  }
  config {
    day = "WEDNESDAY"
    start_time {
      hours   = 0
      minutes = 0
    }
    end_time {
      hours   = 23
      minutes = 59
    }
  }
  config {
    day = "THURSDAY"
    start_time {
      hours   = 0
      minutes = 0
    }
    end_time {
      hours   = 23
      minutes = 59
    }
  }
  config {
    day = "FRIDAY"
    start_time {
      hours   = 0
      minutes = 0
    }
    end_time {
      hours   = 23
      minutes = 59
    }
  }
  config {
    day = "SATURDAY"
    start_time {
      hours   = 0
      minutes = 0
    }
    end_time {
      hours   = 23
      minutes = 59
    }
  }
  config {
    day = "SUNDAY"
    start_time {
      hours   = 0
      minutes = 0
    }
    end_time {
      hours   = 23
      minutes = 59
    }
  }

  tags = {
    Project = var.project_name
  }
}

# 3. Queue — required for routing
resource "aws_connect_queue" "default" {
  instance_id           = aws_connect_instance.this.id
  name                  = "CallerAgentQueue"
  description           = "Default queue for the caller answering agent"
  hours_of_operation_id = aws_connect_hours_of_operation.twenty_four_seven.hours_of_operation_id

  tags = {
    Project = var.project_name
  }
}

# 4. Associate Lex V2 bot with Connect instance
# aws_connect_bot_association only supports Lex V1, so we use the AWS CLI via null_resource
resource "null_resource" "connect_lex_v2_association" {
  triggers = {
    instance_id       = aws_connect_instance.this.id
    lex_bot_alias_arn = local.lex_bot_alias_arn
  }

  provisioner "local-exec" {
    command = "aws connect associate-bot --instance-id ${aws_connect_instance.this.id} --lex-v2-bot AliasArn=${local.lex_bot_alias_arn}"
  }

  depends_on = [awscc_lex_bot_alias.live]
}

# 5. Contact Flow
resource "aws_connect_contact_flow" "caller_agent" {
  instance_id = aws_connect_instance.this.id
  name        = "Caller Agent Flow"
  type        = "CONTACT_FLOW"
  description = "Automated caller answering agent flow"

  content = replace(
    file("${path.module}/../config/contact_flow.json"),
    "$${LEX_BOT_ALIAS_ARN}",
    local.lex_bot_alias_arn
  )

  depends_on = [null_resource.connect_lex_v2_association]

  tags = {
    Project = var.project_name
  }
}

# 6. Claim a Phone Number
resource "aws_connect_phone_number" "caller_agent" {
  target_arn   = aws_connect_instance.this.arn
  country_code = var.connect_phone_country
  type         = var.connect_phone_type

  tags = {
    Project = var.project_name
  }
}

# 7. Associate the phone number with the contact flow
resource "aws_connect_phone_number_contact_flow_association" "caller_agent" {
  phone_number_id = aws_connect_phone_number.caller_agent.id
  instance_id     = aws_connect_instance.this.id
  contact_flow_id = aws_connect_contact_flow.caller_agent.contact_flow_id
}
