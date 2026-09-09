import json
import os

import boto3

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["DYNAMODB_TABLE"])


def lambda_handler(event, context):

    # Increment the visitor counter atomically
    response = table.update_item(
        Key={
            "counter_id": "visitors"
        },
        UpdateExpression="ADD visitor_count :increment",
        ExpressionAttributeValues={
            ":increment": 1
        },
        ReturnValues="UPDATED_NEW"
    )

    visitor_count = int(
        response["Attributes"]["visitor_count"]
    )

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": os.environ["ALLOWED_ORIGIN"]
        },
        "body": json.dumps({
            "visitor_count": visitor_count
        })
    }