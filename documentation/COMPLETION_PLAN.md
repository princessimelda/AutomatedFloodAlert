# Completion plan — 25 November 2026

Updated 22 November 2026, Africa/Nairobi. Source: supplied
`Automated-Alert-System-Specification.pdf` (26 pages, version 1.0).
The PDF is a requirements specification, with no embedded review annotations.
Its technology recommendations are alternatives; they do not require replacing
the existing Flutter, FastAPI or Supabase/PostGIS stack.

## Agreed demonstration scope

The deadline is **25 November 2026**. The user confirmed a working student
prototype with **two channels: an online notification inbox and actual SMS
received on a phone without internet**. SMS still requires a mobile network.
Cached messages, simulated SMS and provider acceptance alone do not prove that
offline requirement. All demonstration alerts are clearly marked TEST.

The completion gate follows PDF section 15: an authenticated source event or
authorised manual entry is evaluated, becomes an alert, is independently
approved, is published through the online inbox and SMS, and is tracked through
acknowledgement or resolution. This is a bounded student demonstration, not an
operational emergency-management deployment.

## Critical path and daily gates

| Date | Work | Required exit evidence | Issues |
| --- | --- | --- | --- |
| 22 Nov | Event validation, rule evaluation, deduplication, approval/publication, immutable audit, durable outbox, Flutter inbox; verify Twilio account eligibility | Isolated DB/API/provider tests pass; reviewer cannot be the creator; unpublished/expired alerts stay hidden; no duplicate publication/SMS jobs | #8, #10, #13, #26 |
| 22 Nov — external dependency | Configure Twilio live sender, credentials, enrolled tester and sufficient sending entitlement | Account can send custom test-alert content to the Kenyan test handset; no secrets in Git/chat | #10, #15 |
| 23 Nov | Apply reviewed migration, connect app/API to hosted database; run delivery worker beside API; verify online inbox and real SMS | Same alert reference visible online and on handset with Wi-Fi/mobile data off; provider delivery state recorded separately from submission | #10, #13, #15, #26 |
| 23 Nov | Connect a checked model event as an informational test input, after delivery works | Rainfall proxy remains informational; manual test-event path remains available for repeatable demo | #8, #9, #13 |
| 24 Nov | Rehearse complete flow; denial/expiry/cancellation/retry/outage checks; narrow-screen and enlarged-text review; freeze changes | Video/screenshots and test report; operator/approver separation; read acknowledgement and resolution evidence; recovery instructions | #25, #26, #27, #29 |
| 25 Nov | Final reproduction and submission | Reviewed merges, known limitations, setup instructions and repeatable demo; no untested late feature expansion | #30 |

Actual SMS eligibility is the earliest external blocker. Twilio trial rules can
restrict custom SMS text; do not assume a free account permits the flood-alert
message. No paid upgrade, sender purchase or live SMS is performed automatically.
The user must complete provider setup and explicitly enable the configured demo.

## Feedback traceability

| PDF requirement | Prototype implementation / decision | Remaining boundary |
| --- | --- | --- |
| §3.1, UC-01: authenticate and validate events; prevent duplicates | Server-scoped integration/operator keys; strict current test events; source/event key plus payload hash; duplicate replay is idempotent, conflicting content is rejected | IoT and independently verified flood sources are not available |
| §3.2–3.3: rules, thresholds and severity | Immutable versioned test rules approved by a configured approver; information/advisory/warning/critical vocabulary; rainfall proxy restricted to information | Official hydrological thresholds and operational approval are absent; live rules editing/escalation remain later |
| §3.4, UC-02–04: create, review, approve, publish | Pending approval → approved → published; independent creator/reviewer; optimistic revisions; public inbox sees only current published alerts | Operator console uses authenticated OpenAPI endpoints; full bespoke administration UI is outside the deadline scope |
| §3.5, UC-10: geographical targeting | One or more catalogue locations per alert; location-filtered inbox; published coverage only | No fabricated flood polygons, population estimates or safe routes; route/geofence work #14 stays separate |
| §3.6, UC-05: two delivery channels | Online inbox job plus tester-allowlisted Twilio SMS outbox; bounded attempts; approved content carries test label, location, time, action and reference | Actual handset receipt must be demonstrated with live credentials; background FCM/email are not claimed |
| §3.7: emergency contacts | Private configured demo-recipient allowlist, at most five testers; numbers never returned in public/admin report DTOs | Organisation/contact CRUD, contact verification and production consent lifecycle remain later |
| §3.8, UC-06: escalation | Audit/revision foundation supports a later policy | Automatic escalation timers and authority hierarchies deferred |
| §3.9, UC-07: acknowledgement | Supabase-verified recipient identity; one acknowledgement per user/alert; timestamp persisted | Reading an alert does not resolve it for everyone or establish safety; response-team assignments deferred |
| §3.10, UC-08–09: updates/cancellation/expiry | Cancel/resolve with reason and audit; pending SMS cancelled; expired alerts hidden at database and app layers | Geographic/severity correction notifications need a later versioned update workflow |
| §3.11, UC-11: delivery monitoring | Attempts separate from alert record; available/queued/processing/retry/accepted/delivered/failed/unknown states; safe failure codes; provider status polling | Ambiguous submissions are held for investigation, not blindly resent; large-scale queue administration deferred |
| §3.12, UC-12: reporting | Restricted alert/channel/status counts and acknowledgement totals; audit/history endpoints | Full exports, load targets and response-time dashboards deferred |
| §4: roles and permissions | Integration, operator and approver service principals stay server-side; ordinary recipients use Supabase sessions | Complete county/organisation roles and user-facing role administration deferred |
| §7–9: APIs, database and integration | Additive `/api/v1` alert endpoints and private Postgres schema; existing `/v1` app endpoints preserved; explicit grants/RLS; UTC times; bounded public view | Apply new migrations only after isolated verification; do not expose private tables through Supabase Data API |
| §10–11: reliability and acceptance | Atomic event/alert/outbox creation; queue deduplication; row-locked claims; redacted errors; automated role, lifecycle, retry and expiry checks | Public hosting, live SMS and physical handset evidence remain release gates |

## Workflow audit — 22 November

- `main` is still `32e6448`; earlier #5/#6/#21 changes are present locally and on
  separate branches, but no corresponding PRs appear in the repository search.
  They must be reviewed/merged rather than described as deployed.
- Latest inspected project-check run, [41863010082](https://github.com/princessimelda/AutomatedFloodAlert/actions/runs/41863010082),
  passed on 4 November. Checks previously ran on PRs/main pushes, leaving
  branch-only work unverified in Actions. Add branch pushes, manual dispatch,
  cancellation of superseded runs, timeouts and an explicitly labelled test-build artifact.
- Latest inspected weather run, [45001244623](https://github.com/princessimelda/AutomatedFloodAlert/actions/runs/45001244623),
  finished ready on 22 November at 08:07 UTC with two predictions. This confirms
  hosted inference; it does not prove app integration or calibrated flood risk.
- [44855980203](https://github.com/princessimelda/AutomatedFloodAlert/actions/runs/44855980203)
  failed on 21 November with `ConnectTimeout`. The provider client already has
  bounded transport retries; do not relabel this external outage as missing retry logic.
- The latest 15 observed weather runs have multi-hour gaps despite the requested
  hourly cron. Scores expire after two hours, so unavailable intervals are expected.
  Keep expiry truthful. Do not use this schedule for time-critical SMS delivery;
  run the durable notification worker beside the API and monitor its health.
- CI builds use a loopback test API URL and no live credentials. They are review
  artifacts, not public deployment bundles.

## Release checklist

- [x] Isolated-tested alert schema applied to the development database; private grants checked.
- [x] Operator/reviewer credentials remain in ignored server configuration.
- [x] Real published test alert parsed by the Dart inbox contract, including area/time/action.
- [ ] Enrolled handset receives matching SMS with internet disabled.
- [ ] Provider acceptance and actual delivery are recorded separately.
- [ ] Signed-in user acknowledgement is stored once and visible in reporting.
- [ ] Resolve/cancel removes current inbox entry and stops eligible unsent SMS.
- [ ] Duplicate, invalid, stale, no-alert and provider failure paths demonstrated.
- [ ] Backend/Flutter checks pass on the exact review commit.
- [ ] Demo evidence, setup/recovery instructions and limitations completed.
- [ ] PRs reviewed/merged and only fully satisfied issues marked Done.

## Deferred work

Further model tuning, calibrated flood labels, verified evacuation routing,
background location, FCM/email, automatic escalations, full agency-role screens,
contact administration and complete bilingual UI are not prerequisites for the
agreed two-channel demonstration. Their existing issues remain open; this plan
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
Actual handset delivery and a real user acknowledgement remain explicit gates.
