import pytest


@pytest.fixture
def apigw_v2_event():
    """Realistic API Gateway v2 HTTP API event (payload format 2.0)."""
    return {
        "version": "2.0",
        "routeKey": "ANY /api/{proxy+}",
        "rawPath": "/api/visitor",
        "rawQueryString": "",
        "headers": {
            "accept": "application/json",
            "content-type": "application/json",
            "host": "abc123.execute-api.us-east-1.amazonaws.com",
            "user-agent": "Mozilla/5.0",
            "x-forwarded-for": "203.0.113.42",
            "x-forwarded-port": "443",
            "x-forwarded-proto": "https",
        },
        "requestContext": {
            "accountId": "123456789012",
            "apiId": "abc123",
            "domainName": "abc123.execute-api.us-east-1.amazonaws.com",
            "domainPrefix": "abc123",
            "http": {
                "method": "GET",
                "path": "/api/visitor",
                "protocol": "HTTP/1.1",
                "sourceIp": "203.0.113.42",
                "userAgent": "Mozilla/5.0",
            },
            "requestId": "req-id-123",
            "routeKey": "ANY /api/{proxy+}",
            "stage": "$default",
            "time": "01/Jan/2025:00:00:00 +0000",
            "timeEpoch": 1735689600000,
        },
        "pathParameters": {"proxy": "visitor"},
        "isBase64Encoded": False,
    }
