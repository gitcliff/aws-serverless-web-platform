import importlib
import json
from unittest.mock import patch, MagicMock

import boto3
import pytest
from moto import mock_aws

TABLE_NAME = "test-visitor-counter"
ALLOWED_ORIGIN = "https://cliffworld.link"

VISITOR_EVENT = {"rawPath": "/api/visitor"}
DASHBOARD_EVENT = {
    "rawPath": "/api/dashboard",
    "requestContext": {
        "authorizer": {
            "jwt": {
                "claims": {"email": "test@example.com"}
            }
        }
    },
}


@pytest.fixture(autouse=True)
def aws_env(monkeypatch):
    """Set required env vars and mock AWS credentials for every test."""
    monkeypatch.setenv("DYNAMODB_TABLE", TABLE_NAME)
    monkeypatch.setenv("ALLOWED_ORIGIN", ALLOWED_ORIGIN)
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")


@pytest.fixture
def handler(aws_env):
    """
    Yield lambda_handler backed by a fresh moto DynamoDB table.

    importlib.reload is required because lambda_function.py initialises the
    boto3 resource and Table at module level. Reloading inside mock_aws() forces
    those references to point at the moto mock rather than a real endpoint.
    """
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


# ── /api/visitor ──────────────────────────────────────────────────────────────

def test_returns_200(handler):
    response = handler(VISITOR_EVENT, None)
    assert response["statusCode"] == 200


def test_first_visit_returns_one(handler):
    response = handler(VISITOR_EVENT, None)
    body = json.loads(response["body"])
    assert body["visitor_count"] == 1


def test_counter_increments_on_each_call(handler):
    handler(VISITOR_EVENT, None)
    response = handler(VISITOR_EVENT, None)
    body = json.loads(response["body"])
    assert body["visitor_count"] == 2


def test_cors_header_matches_allowed_origin(handler):
    response = handler(VISITOR_EVENT, None)
    assert response["headers"]["Access-Control-Allow-Origin"] == ALLOWED_ORIGIN


def test_content_type_is_json(handler):
    response = handler(VISITOR_EVENT, None)
    assert response["headers"]["Content-Type"] == "application/json"


def test_response_body_has_visitor_count(handler):
    response = handler(VISITOR_EVENT, None)
    body = json.loads(response["body"])
    assert "visitor_count" in body
    assert isinstance(body["visitor_count"], int)


def test_dynamodb_error_returns_500(aws_env):
    """When DynamoDB fails, Lambda returns 500 with a safe error message."""
    with mock_aws():
        import lambda_function

        importlib.reload(lambda_function)

        mock_table = MagicMock()
        mock_table.update_item.side_effect = Exception("connection timeout")

        with patch.object(lambda_function, "table", mock_table):
            response = lambda_function.lambda_handler(VISITOR_EVENT, None)

    assert response["statusCode"] == 500
    body = json.loads(response["body"])
    assert body["error"] == "Internal server error"
    assert "timeout" not in json.dumps(body)


def test_error_response_includes_cors_headers(aws_env):
    """Error responses must still include CORS headers for the browser to read them."""
    with mock_aws():
        import lambda_function

        importlib.reload(lambda_function)

        mock_table = MagicMock()
        mock_table.update_item.side_effect = Exception("fail")

        with patch.object(lambda_function, "table", mock_table):
            response = lambda_function.lambda_handler(VISITOR_EVENT, None)

    assert response["headers"]["Access-Control-Allow-Origin"] == ALLOWED_ORIGIN
    assert response["headers"]["Content-Type"] == "application/json"


# ── /api/dashboard ────────────────────────────────────────────────────────────

def test_dashboard_returns_200(handler):
    response = handler(DASHBOARD_EVENT, None)
    assert response["statusCode"] == 200


def test_dashboard_returns_email_from_jwt_claims(handler):
    response = handler(DASHBOARD_EVENT, None)
    body = json.loads(response["body"])
    assert body["email"] == "test@example.com"


def test_dashboard_welcome_message_contains_email(handler):
    response = handler(DASHBOARD_EVENT, None)
    body = json.loads(response["body"])
    assert "test@example.com" in body["message"]


def test_dashboard_falls_back_to_unknown_when_claims_absent(handler):
    event = {"rawPath": "/api/dashboard"}
    response = handler(event, None)
    body = json.loads(response["body"])
    assert body["email"] == "unknown"


# ── unknown path ──────────────────────────────────────────────────────────────

def test_unknown_path_returns_404(handler):
    response = handler({"rawPath": "/api/unknown"}, None)
    assert response["statusCode"] == 404


def test_missing_path_returns_404(handler):
    response = handler({}, None)
    assert response["statusCode"] == 404
