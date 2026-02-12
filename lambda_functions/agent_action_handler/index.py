"""
Bedrock Agent Action Group Lambda Handler.

Handles four API operations:
- GET /check-spam/{phoneNumber} — Check if a phone number is spam
- GET /caller-info/{phoneNumber} — Look up phone number information
- POST /call-record — Save call record to DynamoDB
- POST /notification — Send SNS notification
"""

import json
import os
import uuid
from datetime import datetime, timezone

import boto3
import requests

# Environment variables
TABLE_NAME = os.environ["CALL_RECORDS_TABLE"]
TOPIC_ARN = os.environ["NOTIFICATION_TOPIC_ARN"]
SECRET_NAME = os.environ["NUMVERIFY_SECRET_NAME"]

# AWS clients
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)
sns_client = boto3.client("sns")
secrets_client = boto3.client("secretsmanager")

# Cache the API key across invocations
_numverify_api_key = None


def get_numverify_api_key():
    """Retrieve NumVerify API key from Secrets Manager (cached)."""
    global _numverify_api_key
    if _numverify_api_key is None:
        response = secrets_client.get_secret_value(SecretId=SECRET_NAME)
        secret = json.loads(response["SecretString"])
        _numverify_api_key = secret["api_key"]
    return _numverify_api_key


def check_spam(phone_number: str) -> dict:
    """Check if a phone number is spam using NumVerify API."""
    api_key = get_numverify_api_key()
    url = "http://apilayer.net/api/validate"
    params = {
        "access_key": api_key,
        "number": phone_number,
        "country_code": "",
        "format": 1,
    }

    try:
        response = requests.get(url, params=params, timeout=10)
        response.raise_for_status()
        data = response.json()

        is_valid = data.get("valid", False)
        line_type = data.get("line_type", "unknown")

        # Spam heuristics:
        # 1. Invalid numbers are suspicious
        # 2. VoIP numbers are higher risk (commonly used for spam)
        is_spam = False
        spam_reason = ""

        if not is_valid:
            is_spam = True
            spam_reason = "invalid_number"
        elif line_type == "voip":
            is_spam = False
            spam_reason = "voip_number_flagged_for_review"

        return {
            "is_spam": is_spam,
            "is_valid": is_valid,
            "line_type": line_type or "unknown",
            "carrier": data.get("carrier", "unknown"),
            "country": data.get("country_name", "unknown"),
            "spam_reason": spam_reason,
        }

    except requests.RequestException as e:
        # On API failure, default to not-spam to avoid blocking legitimate calls
        return {
            "is_spam": False,
            "is_valid": True,
            "line_type": "unknown",
            "carrier": "unknown",
            "country": "unknown",
            "spam_reason": f"api_error: {str(e)}",
        }


def get_caller_info(phone_number: str) -> dict:
    """Look up phone number information using NumVerify API."""
    api_key = get_numverify_api_key()
    url = "http://apilayer.net/api/validate"
    params = {
        "access_key": api_key,
        "number": phone_number,
        "format": 1,
    }

    try:
        response = requests.get(url, params=params, timeout=10)
        response.raise_for_status()
        data = response.json()

        return {
            "valid": data.get("valid", False),
            "country_name": data.get("country_name", "unknown"),
            "location": data.get("location", "unknown"),
            "carrier": data.get("carrier", "unknown"),
            "line_type": data.get("line_type", "unknown"),
        }

    except requests.RequestException:
        return {
            "valid": False,
            "country_name": "unknown",
            "location": "unknown",
            "carrier": "unknown",
            "line_type": "unknown",
        }


def save_call_record(body: dict) -> dict:
    """Save call record to DynamoDB."""
    call_id = body.get("call_id", str(uuid.uuid4()))
    timestamp = datetime.now(timezone.utc).isoformat()

    item = {
        "call_id": call_id,
        "timestamp": timestamp,
        "caller_name": body["caller_name"],
        "caller_phone": body["caller_phone"],
        "reason": body["reason"],
        "is_spam": body.get("is_spam", False),
        "call_status": "spam_blocked" if body.get("is_spam") else "completed",
        "notification_sent": False,
    }

    table.put_item(Item=item)

    return {
        "success": True,
        "call_id": call_id,
    }


def send_notification(body: dict) -> dict:
    """Send SNS notification with call details."""
    caller_name = body["caller_name"]
    caller_phone = body["caller_phone"]
    reason = body["reason"]
    call_id = body.get("call_id", "unknown")

    subject = f"Missed Call from {caller_name}"
    message = (
        f"You have a new message from a caller.\n\n"
        f"--- Call Details ---\n"
        f"Caller Name: {caller_name}\n"
        f"Phone Number: {caller_phone}\n"
        f"Reason/Message: {reason}\n"
        f"Call ID: {call_id}\n"
        f"Time: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}\n"
        f"---\n\n"
        f"This message was recorded by your automated caller agent."
    )

    response = sns_client.publish(
        TopicArn=TOPIC_ARN,
        Subject=subject[:100],  # SNS subject max 100 chars
        Message=message,
    )

    # Update DynamoDB record to mark notification as sent
    if call_id != "unknown":
        try:
            table.update_item(
                Key={"call_id": call_id, "timestamp": body.get("timestamp", "")},
                UpdateExpression="SET notification_sent = :val",
                ExpressionAttributeValues={":val": True},
                ConditionExpression="attribute_exists(call_id)",
            )
        except Exception:
            pass  # Non-critical; notification was already sent

    return {
        "success": True,
        "message_id": response["MessageId"],
    }


def extract_path_parameter(event: dict, param_name: str) -> str:
    """Extract a named parameter from the Bedrock Agent event."""
    parameters = event.get("parameters", [])
    for param in parameters:
        if param["name"] == param_name:
            return param["value"]
    return ""


def extract_request_body(event: dict) -> dict:
    """Extract the request body from the Bedrock Agent event."""
    request_body = event.get("requestBody", {})
    content = request_body.get("content", {})
    json_content = content.get("application/json", {})
    properties = json_content.get("properties", [])

    body = {}
    for prop in properties:
        name = prop["name"]
        value = prop["value"]
        # Convert string booleans
        if value in ("true", "True"):
            value = True
        elif value in ("false", "False"):
            value = False
        body[name] = value

    return body


def lambda_handler(event, context):
    """Main Lambda handler for Bedrock Agent action group invocations."""
    api_path = event.get("apiPath", "")
    http_method = event.get("httpMethod", "").upper()

    result = {}

    if api_path.startswith("/check-spam/") and http_method == "GET":
        phone_number = extract_path_parameter(event, "phoneNumber")
        result = check_spam(phone_number)

    elif api_path.startswith("/caller-info/") and http_method == "GET":
        phone_number = extract_path_parameter(event, "phoneNumber")
        result = get_caller_info(phone_number)

    elif api_path == "/call-record" and http_method == "POST":
        body = extract_request_body(event)
        result = save_call_record(body)

    elif api_path == "/notification" and http_method == "POST":
        body = extract_request_body(event)
        result = send_notification(body)

    else:
        result = {"error": f"Unknown action: {http_method} {api_path}"}

    # Format response for Bedrock Agent
    return {
        "messageVersion": "1.0",
        "response": {
            "actionGroup": event.get("actionGroup", ""),
            "apiPath": api_path,
            "httpMethod": http_method,
            "httpStatusCode": 200,
            "responseBody": {
                "application/json": {
                    "body": json.dumps(result),
                },
            },
        },
        "sessionAttributes": event.get("sessionAttributes", {}),
        "promptSessionAttributes": event.get("promptSessionAttributes", {}),
    }
