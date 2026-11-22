"""Twilio adapter: bounded tester allowlist, no secret/body/number logging."""

import re
import unicodedata
from dataclasses import dataclass
from datetime import UTC

import httpx


@dataclass(frozen=True)
class SendResult:
    status: str
    provider_id: str | None = None
    error_code: str | None = None


class TwilioSms:
    def __init__(self, settings, client=None):
        self.settings = settings
        self.client = client or httpx.Client(timeout=15, follow_redirects=False)
        self.owns_client = client is None

    def close(self):
        if self.owns_client:
            self.client.close()

    def credentials(self):
        settings = self.settings
        sid = settings.sms_account_sid.get_secret_value()
        token = settings.sms_auth_token.get_secret_value()
        if not settings.sms_enabled or not re.fullmatch(r"AC[a-fA-F0-9]{32}", sid) or not token:
            raise ValueError("SMS is not configured.")
        return sid, token

    def send(self, job):
        try:
            sid, token = self.credentials()
            sender = self.settings.sms_from.get_secret_value()
            allowed = {s.get_secret_value() for s in self.settings.sms_test_recipients.values()}
            if job["destination"] not in allowed or not all(
                re.fullmatch(r"\+[1-9]\d{7,14}", n) for n in (sender, job["destination"])
            ):
                return SendResult("failed", error_code="recipient_not_allowed")
            issued = job["issued_at"].astimezone(UTC).strftime("%d %b %H:%M UTC")
            expires = job["valid_until"].astimezone(UTC).strftime("%d %b %H:%M UTC")
            # Bound optional summary text rather than cutting the approved action
            # or its expiry off a long multi-location notification.
            location = job["locations"][:60]
            title = job["title"][:60]
            body = f"FLOODSAFE TEST {str(job['alert_id'])[:8]} | {job['severity'].upper()} | {location} | {title} | Issued {issued} | Expires {expires} | {job['recommended_action']}"
            body = unicodedata.normalize("NFKD", body).encode("ascii", "ignore").decode()
            response = self.client.post(
                f"https://api.twilio.com/2010-04-01/Accounts/{sid}/Messages.json",
                auth=(sid, token),
                data={"To": job["destination"], "From": sender, "Body": body},
            )
            if response.status_code == 429:
                return SendResult("retry", error_code="provider_rate_limit")
            if 400 <= response.status_code < 500:
                return SendResult("failed", error_code="provider_rejected")
            if response.status_code != 201:
                return SendResult("unknown", error_code="provider_uncertain")
            message_id = response.json().get("sid", "")
            if not re.fullmatch(r"SM[a-fA-F0-9]{32}", message_id):
                return SendResult("unknown", error_code="invalid_provider_receipt")
            return SendResult("accepted", provider_id=message_id)
        except (httpx.ConnectError, httpx.ConnectTimeout):
            return SendResult("retry", error_code="connect_failed")
        except (httpx.HTTPError, ValueError, TypeError):
            # A timeout after submission may already have sent the SMS. Do not
            # blindly retry an ambiguous submission and send duplicate warnings.
            return SendResult("unknown", error_code="submission_uncertain")

    def delivery(self, message_id):
        if not re.fullmatch(r"SM[a-fA-F0-9]{32}", message_id or ""):
            return None
        try:
            sid, token = self.credentials()
            response = self.client.get(
                f"https://api.twilio.com/2010-04-01/Accounts/{sid}/Messages/{message_id}.json",
                auth=(sid, token),
            )
            response.raise_for_status()
            status = response.json().get("status")
            return (
                "delivered"
                if status == "delivered"
                else "failed"
                if status in {"failed", "undelivered", "canceled"}
                else None
            )
        except (httpx.HTTPError, ValueError, TypeError):
            return None
