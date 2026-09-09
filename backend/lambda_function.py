import json
import logging
import os

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["DYNAMODB_TABLE"])


def lambda_handler(event, context):
    # Structured log fields present on every entry — queryable in Logs Insights
    request_id = context.aws_request_id if context else "local"
    environment = os.environ.get("ENVIRONMENT", "unknown")

    headers = {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": os.environ["ALLOWED_ORIGIN"],
    }

    try:
        response = table.update_item(
            Key={"counter_id": "visitors"},
            UpdateExpression="ADD visitor_count :increment",
            ExpressionAttributeValues={":increment": 1},
            ReturnValues="UPDATED_NEW",
        )

        visitor_count = int(response["Attributes"]["visitor_count"])

        logger.info(json.dumps({
            "action": "increment_visitor_count",
            "visitor_count": visitor_count,
            "request_id": request_id,
            "environment": environment,
        }))

        return {
            "statusCode": 200,
            "headers": headers,
            "body": json.dumps({"visitor_count": visitor_count}),
        }

    except ClientError as e:
        logger.error(json.dumps({
            "action": "increment_visitor_count",
            "error": e.response["Error"]["Code"],
            "message": e.response["Error"]["Message"],
            "request_id": request_id,
            "environment": environment,
        }))
        return {
            "statusCode": 500,
            "headers": headers,
            "body": json.dumps({"error": "Internal server error"}),
        }

    except Exception as e:
        logger.error(json.dumps({
            "action": "increment_visitor_count",
            "error": type(e).__name__,
            "message": str(e),
            "request_id": request_id,
            "environment": environment,
        }))
        return {
            "statusCode": 500,
            "headers": headers,
            "body": json.dumps({"error": "Internal server error"}),
        }
