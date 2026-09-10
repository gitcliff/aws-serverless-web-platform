import json
import logging
import os
import time

import boto3
from aws_xray_sdk.core import patch_all, xray_recorder
from botocore.exceptions import ClientError

# Patch boto3 so DynamoDB calls appear as subsegments in X-Ray traces.
# LOG_ERROR prevents SegmentNotFoundException when running outside a Lambda
# context (e.g., local tests), so the function degrades gracefully.
xray_recorder.configure(context_missing="LOG_ERROR")
patch_all()

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["DYNAMODB_TABLE"])


def lambda_handler(event, context):
    # Structured log fields present on every entry — queryable in Logs Insights
    request_id = context.aws_request_id if context else "local"
    environment = os.environ.get("ENVIRONMENT", "unknown")
    # Propagate X-Ray trace ID so Lambda logs, API GW logs, and X-Ray traces
    # can all be correlated by a single ID in Logs Insights queries
    trace_id = (event.get("headers") or {}).get("x-amzn-trace-id", "none")

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
            "trace_id": trace_id,
            "environment": environment,
        }))

        # Emit Embedded Metric Format line — the CloudWatch Logs agent
        # automatically extracts VisitorCount into the
        # VisitorCounter/Application custom namespace with no extra SDK needed.
        print(json.dumps({
            "_aws": {
                "Timestamp": int(time.time() * 1000),
                "CloudWatchMetrics": [{
                    "Namespace": "VisitorCounter/Application",
                    "Dimensions": [["Environment"]],
                    "Metrics": [{"Name": "VisitorCount", "Unit": "Count"}],
                }],
            },
            "Environment": environment,
            "VisitorCount": visitor_count,
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
            "trace_id": trace_id,
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
            "trace_id": trace_id,
            "environment": environment,
        }))
        return {
            "statusCode": 500,
            "headers": headers,
            "body": json.dumps({"error": "Internal server error"}),
        }
