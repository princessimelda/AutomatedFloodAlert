# Flutter core flow

Update: the app now also has an API repository for place selection, risk summaries and published advisories. See [backend setup and HTTP contracts](../../backend/README.md) and [database design](../../supabase/README.md). The original standalone mode described below remains available without `FLOODSAFE_API_URL`. In API mode, GPS is transient POST input, not persisted; it is no longer accurate to describe that mode as making no backend requests.

This increment supports issues [#13](https://github.com/princessimelda/AutomatedFloodAlert/issues/13) and [#23](https://github.com/princessimelda/AutomatedFloodAlert/issues/23), foreground-location work in [#12](https://github.com/princessimelda/AutomatedFloodAlert/issues/12), and accessibility work in [#25](https://github.com/princessimelda/AutomatedFloodAlert/issues/25). It does not complete those issues or the backend API issue #8.

## Entry and information hierarchy

- Home is available without phone verification and starts with no assumed place.
- The reading order is selected place, current situation, and next action. Preparedness steps remain accessible using a persistent labelled button.
- The sample map is optional and accompanied by a text description. No unverified route is presented as an action.
- The existing sample news and scripted assistant remain available. Authentication remains an explicitly labelled optional preview.

## Data and state boundaries

`DashboardRepository` supplies `DashboardData` for a `Place`. `DashboardController` owns asynchronous loading, retry, response matching, and validity. Widgets consume those states rather than assign a risk when a place is tapped.

| Scenario | Expected result |
| --- | --- |
| No place | Prompt to select a place; guidance still available |
| Pending request | Old place assessment cleared immediately |
| Kibera fixture | Explicitly labelled sample high risk |
| Kasarani fixture | Explicitly labelled sample low risk |
| Westlands fixture | Risk unavailable, not low risk |
| Embakasi fixture | Out of date; no current severity claim |
| Validity expires while open | Situation changes to out of date |
| Future issue time | Not treated as a current assessment |
| Repository failure/timeout | Recoverable error and retry |
| Old request finishes after a newer selection | Old response ignored |
| Response place ID does not match | Error, never another place's risk |
| Refresh fixture | Original validity retained, not extended |
| GPS coordinates | Risk unavailable; no inferred sample-area assessment |

Fixtures are created relative to session time to exercise validity behaviour. Their source and timestamps are scenario metadata, not evidence of current conditions. No live weather, risk, or backend request is made.

## Foreground location

`ForegroundLocationService` requests one fix only after an explicit button press. Android declares coarse/fine foreground location and internet permissions; it does not declare background location. Web requires HTTPS or localhost.

The service handles disabled services, permission denial/permanent denial, and browser permission-query limitations. It rejects fixes older than two minutes, more than 30 seconds in the future, with accuracy worse than 250 metres, or with invalid coordinates. Those are initial application thresholds, not proof of sufficient accuracy for an eventual flood polygon lookup.

A manual selection supersedes an outstanding GPS request. Coordinates and accuracy are displayed with capture time, remain in memory, and are not uploaded or persisted. No reverse geocoding or background tracking is performed. Authentication, coordinate ownership, retention and upload intervals must be addressed before backend telemetry is introduced.

## Accessibility and guidance

- Severity uses a text label and icon as well as colour.
- Home headings have semantic heading roles; changing status/error text uses live regions.
- Core buttons have text labels; profile has a tooltip. Text and warning colours have stronger contrast than the original palette.
- Layouts scroll and wrap with enlarged text; the place picker is scrollable and does not require GPS.
- Tests cover the Home touch-target, label, and text-contrast guidelines and the core flow at 200% text scale on narrow and short viewports.
- Physical TalkBack/VoiceOver, keyboard-only browser use, translated content, and first-use usability sessions remain to be verified. This is not a WCAG conformance claim.

Preparedness content is adapted from [CDC, Preparing for Floods](https://www.cdc.gov/floods/safety/) (consulted 2026-10-28). It is general education, not a Nairobi emergency bulletin or route instruction. Local review and English/Kiswahili localisation remain outstanding.

## Verification and next boundary

Run `flutter analyze`, `flutter test`, and `flutter build web --no-web-resources-cdn` from `floodsafe/`. Static analysis, all 27 tests, and the web build passed for this increment. Widget tests inject repository failures and location outcomes; location-service tests use a fake platform. Real permission prompts and GPS accuracy still require device/browser testing.

Next, agree the authenticated backend contract and schema (#6–#8), implement a repository that parses and validates backend responses, and add persistent sessions and approved advisory data. Keep fixtures available only as explicit demo/test data. Do not mark #12, #13, #23, #25, or #29 complete based on this increment: background location, live data, localisation, human accessibility checks, and CI remain outstanding.

The 0.1.0 APK and existing published web snapshot are unchanged. This increment is for local development; it does not publish a site or generate another APK.
