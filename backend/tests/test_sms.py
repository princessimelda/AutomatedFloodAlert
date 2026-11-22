from datetime import UTC, datetime, timedelta

import httpx
import pytest

from app.config import Settings
from app.sms import TwilioSms


def configured():
    return Settings(
        _env_file=None,
        sms_enabled=True,
        sms_account_sid="AC" + "a" * 32,
        sms_auth_token="test-secret-token",
        sms_from="+15005550006",
        sms_test_recipients={"tester": "+15005550009"},
    )


def job():
    return {
        "destination": "+15005550009",
        "alert_id": "12345678-test",
        "severity": "information",
        "locations": "Kibera",
        "title": "Practice",
        "issued_at": datetime.now(UTC),
        "valid_until": datetime.now(UTC) + timedelta(hours=1),
        "recommended_action": "Read the test alert.",
    }


def test_submission_is_accepted_not_delivered_and_only_test_content_is_sent():
    calls = []

    def handler(request):
        calls.append(request)
        if request.method == "POST":
            assert "FLOODSAFE+TEST" in request.content.decode()
            assert "Expires" in request.content.decode()
            assert request.url.host == "api.twilio.com"
            return httpx.Response(201, json={"sid": "SM" + "b" * 32, "status": "queued"})
        return httpx.Response(200, json={"status": "delivered"})

    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        sms = TwilioSms(configured(), client)
        result = sms.send(job())
        assert result.status == "accepted"
        assert sms.delivery(result.provider_id) == "delivered"
        assert len(calls) == 2


@pytest.mark.parametrize(
    "code,expected", [(429, "retry"), (400, "failed"), (401, "failed"), (500, "unknown")]
)
def test_provider_errors_do_not_become_delivery_success(code, expected):
    with httpx.Client(transport=httpx.MockTransport(lambda _: httpx.Response(code))) as client:
        assert TwilioSms(configured(), client).send(job()).status == expected


@pytest.mark.parametrize(
    "exception,expected", [(httpx.ReadTimeout, "unknown"), (httpx.ConnectTimeout, "retry")]
)
def test_uncertain_submission_is_not_blindly_retried(exception, expected):
    def handler(request):
        raise exception("secret endpoint detail must not escape")

    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        result = TwilioSms(configured(), client).send(job())
        assert result.status == expected
        assert "secret" not in repr(result)


def test_recipient_outside_allowlist_never_contacts_provider():
    def handler(request):
        pytest.fail("Unenrolled recipient was submitted")

    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        result = TwilioSms(configured(), client).send({**job(), "destination": "+15005550008"})
        assert result.status == "failed"


def test_long_location_summary_keeps_complete_action_and_expiry():
    from urllib.parse import parse_qs

    action = "Follow the TEST exercise instructions. " * 7

    def handler(request):
        body = parse_qs(request.content.decode())["Body"][0]
        assert body.endswith(action)
        assert "Expires" in body and len(body) < 600
        return httpx.Response(201, json={"sid": "SM" + "b" * 32})

    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        result = TwilioSms(configured(), client).send(
            {
                **job(),
                "locations": "Area, " * 100,
                "title": "Long title " * 30,
                "recommended_action": action,
            }
        )
        assert result.status == "accepted"
