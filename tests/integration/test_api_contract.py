"""Integration tests that validate the Lambda handler against realistic
API Gateway v2 events (payload format 2.0) rather than empty dicts."""

import importlib
import json

import boto3
import pytest
from moto import mock_aws

TABLE_NAME = "test-visitor-counter"
ALLOWED_ORIGIN = "https://cliffworld.link"


@pytest.fixture(autouse=True)
def aws_env(monkeypatch):
    monkeypatch.setenv("DYNAMODB_TABLE", TABLE_NAME)
    monkeypatch.setenv("ALLOWED_ORIGIN", ALLOWED_ORIGIN)
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")


@pytest.fixture
def handler(aws_env):
    with mock_aws():
        ddb = boto3.resource("dynamodb", region_name="us-east-1")
        ddb.create_table(
            TableName=TABLE_NAME,
            KeySchema=[{"AttributeName": "counter_id", "KeyType": "HASH"}],
            AttributeDefinitions=[
                {"AttributeName": "counter_id", "AttributeType": "S"}
            ],
            BillingMode="PAY_PER_REQUEST",
        )
        import lambda_function

        importlib.reload(lambda_function)
        yield lambda_function.lambda_handler


@pytest.mark.integration
class TestApiContract:
    """Validate that Lambda responses conform to the API Gateway v2 response contract."""

    def test_response_has_required_fields(self, handler, apigw_v2_event):
        response = handler(apigw_v2_event, None)
        assert "statusCode" in response
        assert "headers" in response
        assert "body" in response

    def test_status_code_is_int(self, handler, apigw_v2_event):
        response = handler(apigw_v2_event, None)
        assert isinstance(response["statusCode"], int)

    def test_body_is_valid_json_string(self, handler, apigw_v2_event):
        response = handler(apigw_v2_event, None)
        body = json.loads(response["body"])
        assert isinstance(body, dict)

    def test_visitor_count_is_positive_integer(self, handler, apigw_v2_event):
        response = handler(apigw_v2_event, None)
        body = json.loads(response["body"])
        assert isinstance(body["visitor_count"], int)
        assert body["visitor_count"] > 0

    def test_cors_origin_is_exact_not_wildcard(self, handler, apigw_v2_event):
        response = handler(apigw_v2_event, None)
        origin = response["headers"]["Access-Control-Allow-Origin"]
        assert origin == ALLOWED_ORIGIN
        assert origin != "*"

    def test_content_type_header_present(self, handler, apigw_v2_event):
        response = handler(apigw_v2_event, None)
        assert response["headers"]["Content-Type"] == "application/json"

    def test_counter_increments_with_realistic_events(self, handler, apigw_v2_event):
        """Two calls with realistic events should produce incrementing counts."""
        handler(apigw_v2_event, None)
        response = handler(apigw_v2_event, None)
        body = json.loads(response["body"])
        assert body["visitor_count"] == 2
