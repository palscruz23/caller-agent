# -----------------------------------------------------
# DynamoDB Table — stores call records
# -----------------------------------------------------

resource "aws_dynamodb_table" "call_records" {
  name         = "${var.project_name}-call-records"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "call_id"
  range_key    = "timestamp"

  attribute {
    name = "call_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  attribute {
    name = "caller_phone"
    type = "S"
  }

  global_secondary_index {
    name            = "phone-number-index"
    hash_key        = "caller_phone"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Project = var.project_name
  }
}
