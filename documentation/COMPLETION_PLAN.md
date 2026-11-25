# Completion plan — 25 November 2026

Updated 25 November 2026, Africa/Nairobi. Source: supplied
`Automated-Alert-System-Specification.pdf` (26 pages, version 1.0).
The PDF is a requirements specification, with no embedded review annotations.
Its technology recommendations are alternatives; they do not require replacing
the existing Flutter, FastAPI or Supabase/PostGIS stack.

## Agreed demonstration scope — revised 25 November

The user confirmed **email authentication and in-app notifications** as the
release scope. Actual SMS/offline messaging is deferred because the provider
cost is unaffordable. This supersedes the earlier two-channel acceptance gate;
no further supervisor approval is pending for that budget decision. Keep
`FLOODSAFE_SMS_ENABLED=false` and `FLOODSAFE_NOTIFICATION_WORKER_ENABLED=false`.
Do not purchase a Twilio number or enable sending for this release.

The bounded student demonstration is: authenticated source event or authorised
manual entry → rule evaluation → independent approval → publication → online
inbox → signed-in acknowledgement → resolution/cancellation. The inbox refreshes
while open; background push and receipt of new alerts without internet are not
implemented. All demonstration alerts remain labelled TEST.

## Remaining completion gates

| Order | Work | Required evidence | Issues |
| --- | --- | --- | --- |
| 1 | Public Render API and Flutter deployment with existing Supabase | HTTPS readiness, correct CORS, real email confirmation redirect, persistent session and saved places | #8, #11, #13, #29, #30 |
| 2 | Read fresh persisted rainfall predictions through API into Flutter | Source/model/issue/expiry visible; stale or missing inputs unavailable; no flood-probability claim | #8, #9, #13 |
| 3 | Connect valid model events to the existing reviewed alert lifecycle | Deterministic event identity, informational rainfall proxy, no duplicate publication, authenticated acknowledgement and resolution | #10, #26 |
| 4 | Usability and accessibility review on the hosted app | Clear first action, area/context, narrow screens, enlarged text, useful loading/empty/error states | #22, #23, #24, #25 |
| 5 | Final reproduction, regression checks and release evidence | Exact-commit CI, hosted acceptance results, achieved timings, setup/recovery guide, reviewed merges | #26, #27, #29, #30 |

[Render deployment instructions](RENDER_DEPLOYMENT.md) describe the paid API and
free static site. GitHub repository authorisation lets Render fetch source; it
does not itself create services or configure secrets. Actual public URLs and
service health must be verified before claiming deployment is complete.

## Feedback traceability

| PDF requirement | Prototype implementation / decision | Remaining boundary |
| --- | --- | --- |
| §3.1, UC-01: authenticate and validate events; prevent duplicates | Server-scoped integration/operator keys; strict current test events; source/event key plus payload hash; duplicate replay is idempotent, conflicting content is rejected | IoT and independently verified flood sources are not available |
| §3.2–3.3: rules, thresholds and severity | Immutable versioned test rules approved by a configured approver; information/advisory/warning/critical vocabulary; rainfall proxy restricted to information | Official hydrological thresholds and operational approval are absent; live rules editing/escalation remain later |
| §3.4, UC-02–04: create, review, approve, publish | Pending approval → approved → published; independent creator/reviewer; optimistic revisions; public inbox sees only current published alerts | Operator console uses authenticated OpenAPI endpoints; full bespoke administration UI is outside the deadline scope |
| §3.5, UC-10: geographical targeting | One or more catalogue locations per alert; location-filtered inbox; published coverage only | No fabricated flood polygons, population estimates or safe routes; route/geofence work #14 stays separate |
| §3.6, UC-05: two delivery channels | Online inbox job plus tester-allowlisted Twilio SMS outbox; bounded attempts; approved content carries test label, location, time, action and reference | SMS deferred by the 25 November budget decision; in-app receipt is the release gate; background FCM/email are not claimed |
| §3.7: emergency contacts | Private configured demo-recipient allowlist, at most five testers; numbers never returned in public/admin report DTOs | Organisation/contact CRUD, contact verification and production consent lifecycle remain later |
| §3.8, UC-06: escalation | Audit/revision foundation supports a later policy | Automatic escalation timers and authority hierarchies deferred |
| §3.9, UC-07: acknowledgement | Supabase-verified recipient identity; one acknowledgement per user/alert; timestamp persisted | Reading an alert does not resolve it for everyone or establish safety; response-team assignments deferred |
| §3.10, UC-08–09: updates/cancellation/expiry | Cancel/resolve with reason and audit; pending SMS cancelled; expired alerts hidden at database and app layers | Geographic/severity correction notifications need a later versioned update workflow |
| §3.11, UC-11: delivery monitoring | Attempts separate from alert record; available/queued/processing/retry/accepted/delivered/failed/unknown states; safe failure codes; provider status polling | Ambiguous submissions are held for investigation, not blindly resent; large-scale queue administration deferred |
| §3.12, UC-12: reporting | Restricted alert/channel/status counts and acknowledgement totals; audit/history endpoints | Full exports, load targets and response-time dashboards deferred |
| §4: roles and permissions | Integration, operator and approver service principals stay server-side; ordinary recipients use Supabase sessions | Complete county/organisation roles and user-facing role administration deferred |
| §7–9: APIs, database and integration | Additive `/api/v1` alert endpoints and private Postgres schema; existing `/v1` app endpoints preserved; explicit grants/RLS; UTC times; bounded public view | Apply new migrations only after isolated verification; do not expose private tables through Supabase Data API |
| §10–11: reliability and acceptance | Atomic event/alert/outbox creation; queue deduplication; row-locked claims; redacted errors; automated role, lifecycle, retry and expiry checks | Public hosting and real signed-in acknowledgement remain release gates; SMS is outside the revised release scope |

## Workflow audit

Main contains merged PR #34 at `be56b2d` (22 November), including the alert inbox,
controlled event lifecycle and CI improvements. Issues #5/#6/#21 were closed by
that merge. On 25 November, the fetched local main matched origin/main before
Render preparation; no open PRs were returned by the repository search.

The 22 November main checks and cloud rainfall worker passed. Those historical
results do not verify the new deployment commit; inspect the new run before
merging. Project checks cover branch pushes/PRs, superseded-run cancellation,
timeouts and a labelled web test artifact. The artifact uses a loopback API URL
and is not a deployable public release.

The weather schedule requests hourly runs but observed multi-hour gaps and
provider timeouts. Scores expire after two hours. Preserve truthful unavailable
states; neither cron success nor the experimental score establishes a flood
warning. Existing bounded transport retries are already implemented.

## Release checklist

- [x] Isolated-tested alert schema applied to the development database; private grants checked.
- [x] Operator/reviewer credentials remain in ignored server configuration.
- [x] Real published test alert parsed by the Dart inbox contract, including area/time/action.
- [x] SMS deferred explicitly due to cost; no offline delivery claim.
- [ ] Public Render services and hosted email confirmation/session flows verified.
- [ ] Signed-in user acknowledgement is stored once and visible in reporting.
- [ ] Resolve/cancel removes current inbox entry; no SMS jobs are created in the revised release.
- [ ] Duplicate, invalid, stale, no-alert and provider failure paths demonstrated.
- [ ] Backend/Flutter checks pass on the exact review commit.
- [ ] Demo evidence, setup/recovery instructions and limitations completed.
- [ ] PRs reviewed/merged and only fully satisfied issues marked Done.

## Deferred work

Further model tuning, calibrated flood labels, verified evacuation routing,
background location, FCM/email, automatic escalations, full agency-role screens,
contact administration and complete bilingual UI are not prerequisites for the
agreed online demonstration. SMS and offline messaging are also deferred by explicit user decision. Their existing issues remain open; this plan
does not silently drop their acceptance criteria.

Provider references checked 22 November:
[Twilio trial restrictions](https://www.twilio.com/docs/usage/trials),
[Messages API](https://www.twilio.com/docs/messaging/api/message-resource),
[Africa's Talking sandbox limitation](https://help.africastalking.com/en/articles/1170660-how-do-i-get-started-on-the-africa-s-talking-sandbox).

## Verification recorded on 22 November

The local API `/readyz` passed against Supabase. An operator created a controlled
event, a separate reviewer approved it, and the operator published it. Replaying
the event returned the same reference without duplication. The Dart client parsed
four catalogue places, five guide answers and the published test alert. There
were no current seeded advisories, correctly reflecting their expiry.

The live verification created only an `in_app` job; SMS was disabled and no SMS
was sent. A private ignored verification receipt records the alert ID/time.
The 54 backend tests cover the mocked SMS path, independent approval, owner
acknowledgement, bounded retries, concurrent claims, expiry and cancellation.
The 15 weather/persistence tests and two CLI-summary tests also passed.
Flutter's 65 tests passed, including the new inbox tests at 200% text. The web
build succeeded and the API container imported without private configuration.
Actual handset delivery was an earlier gate and is now deferred; a real signed-in user acknowledgement remains required.
