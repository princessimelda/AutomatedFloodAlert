# Online student prototype

Scope updated 25 November 2026: email authentication and in-app notifications.
The user confirmed that SMS is outside the release scope because of provider
costs. Keep both SMS and the notification worker disabled. The optional SMS
instructions below are retained for future work, not current acceptance gates.
The inbox polls while open; no background push or offline receipt is claimed.

Read [the completion plan](COMPLETION_PLAN.md) for the deadline, scope and feedback
mapping. This guide demonstrates controlled TEST events, not official warnings.

## Setup

1. Install the pinned backend requirements using a local virtual environment.
2. Keep the existing ignored `backend/.env` database configuration. Add the fields
   from [notifications.example.env](../backend/notifications.example.env) to ignored
   `backend/.env.notifications`. A private file with generated operator credentials
   was prepared locally; do not overwrite it or paste it into chat.
3. Configure `AUTH_URL` and the project's publishable key for Supabase recipient
   verification. Administrative service-role credentials are not used in Flutter.
4. After isolated verification/review, apply the new migration with
   `python -m app.manage migrate` from `backend/`. Never run the test suite against
   Supabase. `/readyz` checks that the alert schema is present.
5. Start locally with `python -m uvicorn app.main:app --host 127.0.0.1 --port 8001 --no-access-log`.
   Build Flutter using its existing ignored config, with `FLOODSAFE_API_URL` pointing
   to this API. Keep the browser origin in the exact backend CORS allowlist.

On a fresh checkout, `python -m app.provision_alert_demo` from `backend/` generates
unique role keys and a mode-0600 notification file, preserving any existing file.
The example configuration keeps privileged writes disabled until credentials are
provisioned; it contains no reusable operator keys.

Operator/reviewer keys remain on the server or in the local demo console. They
are not shared public-user credentials. Supabase sign-in identifies ordinary
recipients when acknowledging an alert.

## Operator demonstration

Open the local API `/docs`. The authenticated OpenAPI console is the prototype's
operator interface; a separate polished administration website is not required
for this deadline.

1. **Reviewer:** use the `X-FloodSafe-Key` security scheme with the reviewer key
   from the private local file. `POST /api/v1/alert-rules` with a unique name,
   version 1, event_kind `manual_report`, threshold 1 and severity `warning`.
   Save the returned rule UUID. These are synthetic demonstration settings.
2. **Operator:** change to the operator key. `POST /api/v1/alerts` with a unique
   source_event_id, that rule UUID, event_kind `manual_report`, metric 1,
   current UTC occurred_at, valid_until one hour later, evidence stating that it
   is a controlled test, a short title/message/action and `place_ids: ["kibera"]`.
   `is_demo` must remain true. The result is pending approval, not public.
3. Repeat the same request: it must return `duplicate` with the same event/alert
   IDs. Changing content under the same source/event ID must produce conflict.
4. `GET /api/v1/admin/alerts/{id}` to review evidence and current revision.
   Attempting to publish before approval must fail.
5. **Independent reviewer:** `POST /api/v1/alerts/{id}/approve` with
   expected_revision 1 and an audit reason. Creator and reviewer must differ.
6. **Operator or reviewer:** `POST /api/v1/alerts/{id}/publish` with
   expected_revision 2 and a reason. Publication atomically creates the online
   inbox record and, when enabled, the enrolled-tester SMS jobs. Replaying this
   publication must not create duplicate jobs.
7. **Recipient:** open Flutter → Alerts. Confirm TEST label, area, severity,
   issue/expiry times, action and the same eight-character reference as the SMS.
   The inbox refreshes every 30 seconds while open; Refresh checks immediately.
8. Sign in with the existing Supabase account and select “I have read this alert”.
   The backend verifies the session with Supabase and stores one acknowledgement
   per user/alert. Acknowledgement does not resolve the alert for other users.
9. Inspect `/api/v1/notifications`, `/api/v1/reports/alerts` and
   `/api/v1/admin/alerts/{id}/audit` with an operator key. Phone numbers and secrets
   are not part of these response contracts.
10. Resolve or cancel using current revision 3 and a reason. The current inbox
    entry disappears on refresh; eligible unsent jobs are cancelled. Historical
    delivery/audit records remain.

`POST /api/v1/events` uses the integration/operator key for the equivalent
component-event path. A rainfall_proxy rule is restricted to `information` severity;
the existing rainfall model is not a calibrated flood probability.

## Future extension: real SMS (outside release scope)

Configure Twilio Account SID, Auth Token, an SMS-capable sender and up to five
explicitly enrolled tester destinations in E.164 format. Confirm that the account
can send custom alert text to the intended country. Current trial restrictions
may block this even when login and credentials work; provider test credentials or
virtual phones do not establish physical offline delivery.

Only after configuration and explicit test authorisation, set both
`FLOODSAFE_SMS_ENABLED=true` and `FLOODSAFE_NOTIFICATION_WORKER_ENABLED=true`, then
restart the API. New publications queue SMS; publications made while SMS was
disabled do not silently send retrospectively. Use a new controlled test alert.

For the handset test, turn off Wi-Fi and mobile data, retain SIM/mobile network
coverage, publish the test and record receipt with its reference and time. The
SMS prefix is always `FLOODSAFE TEST`. Restore internet to acknowledge in the app.
Actual handset evidence remains required even when mocked provider tests pass.

The demo allowlist is not a geofenced population list: all enabled enrolled
testers receive the published test SMS. Geographic subscriptions remain #14.
SMS contains issue/expiry times and the approved action. Long location/title
summaries are shortened; long messages may use multiple billable SMS segments.

The API worker submits one queued SMS per tick, polls accepted Twilio messages
for delivery status, and retains each attempt. `accepted` is distinct from
`delivered`; unknown submissions are held rather than blindly resent. Retryable
connection/rate-limit errors have at most three attempts. Rejected messages fail
explicitly. A process interrupted during submission leaves a durable record that
becomes `unknown` for investigation after five minutes.

## Verification and deployment

```bash
# From backend/; isolated loopback database only:
FLOODSAFE_RUN_DB_TESTS=1 python -m pytest -q
# From floodsafe/:
flutter analyze
flutter test
flutter build web --dart-define-from-file=config.local.json
```

Build the API container with `docker build -t floodsafe-api -f backend/Dockerfile backend`.
Its build context excludes credentials. Supply configuration as hosting-provider
secrets; the API listens on `PORT` (default 8000). Run it on a long-lived service
so the delivery loop can progress. A static Flutter host or a request-only
serverless function does not run this worker continuously. Keep frontend/API URLs,
CORS and Supabase confirmation redirects aligned when a public host is chosen.

Do not use the delayed GitHub weather cron for SMS dispatch. Database outbox
claims protect concurrent API workers; unresolved/ambiguous sends are visible for
review. Neither RabbitMQ nor Redis is needed for this small prototype.

The CI web artifact points at a loopback test API and contains no live account
configuration. It is a review build, not the final public deployment.

Provider references: [Twilio trial restrictions](https://www.twilio.com/docs/usage/trials),
[Messages API and delivery states](https://www.twilio.com/docs/messaging/api/message-resource),
[Supabase Auth JWT guidance](https://supabase.com/docs/guides/auth/jwts).
