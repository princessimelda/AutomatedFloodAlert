# Chapter 5: System Implementation, Testing and Evaluation

**Project:** Automated Flood Alert — FloodSafe, Nairobi
**Document status:** Working Chapter 5 draft, based on implementation evidence available on 29 October 2026
**Application evidence baseline:** Commit `e60edd5`, with backend/database commit `8057174`; integrated through PR #31 as merge `156546f7`
**Presentation:** Text and tables only; no images, diagrams or screenshots are included.

This document follows the applicable Chapter 5 structure in *Research Writing for CS 2 Projects — 2026*, supplied as `Research%20Writing%20for%20CS%202%20Projects%20-%202026.pdf.pdf`, PDF pages 79–99. FloodSafe is a hybrid application and machine-learning research project; the software and AI/ML routes were therefore combined. The hardware-assembly, IoT, blockchain and specialised cybersecurity routes do not describe the implemented project and were omitted.

The draft distinguishes implementation, automated verification, informal demonstration and outstanding evaluation. Historical development results are identified as such; no new training, final test-set evaluation or user study was conducted to prepare this document. The section numbering, formal research-objective wording and Chapter 4 requirement identifiers remain subject to reconciliation with the approved proposal and supervisor guidance. The GitHub issue references below provide existing development traceability, rather than invented approved requirement IDs.

## Contents

- [5.1 Introduction](#51-introduction)
- [5.2 Implementation Environment](#52-implementation-environment)
- [5.3 System Implementation](#53-system-implementation)
- [5.4 Testing and Evaluation](#54-testing-and-evaluation)
- [5.5 Version Control and Implementation Evidence](#55-version-control-and-implementation-evidence)
- [5.6 Author Oversight and Use of AI-Assisted Tools](#56-author-oversight-and-use-of-ai-assisted-tools)
- [5.7 Evaluation Results, Discussion and Limitations](#57-evaluation-results-discussion-and-limitations)

## 5.1 Introduction

The project investigated flood-related risk in Nairobi and developed FloodSafe as an interface for location selection, risk-information presentation and preparedness guidance. Implementation proceeded incrementally: a demonstration interface was extended with typed data services, a PostgreSQL/PostGIS database, a Python API, optional authentication, saved places, a database-backed guide and an interactive geographic map.

Two implementation tracks were maintained. The application track provided a connected development prototype. The research track compared models for retrospective simulated high-flow classification. These tracks had not yet been joined into an operational prediction-to-alert service. The application’s seeded low, moderate or high severity vocabulary must therefore not be interpreted as the output of an evaluated three-class flood prediction model.

This chapter records the environment, implemented components, integration decisions, observed checks and limitations. Its evidence supports a functioning application foundation and preliminary model investigation. It does not establish accurate real-world flood forecasting, verified evacuation guidance or readiness for public emergency use.

## 5.2 Implementation Environment

### 5.2.1 Hardware and Deployment Environment

Development and browser demonstrations were performed on a MacBook Pro. The development workstation was inspected when preparing this draft; these observations describe an available environment, not experimentally established minimum requirements. The historical model-training machine and computing budget were not independently established from the retained experiment metadata.

**Table 5.1: Recorded development, test and deployment environments**

| Layer | Recorded configuration | Role and evidence boundary |
| --- | --- | --- |
| Development workstation | MacBook Pro, model identifier `MacBookPro16,2`; x86-64 architecture; 16 GiB installed memory; 8 reported CPU slots; macOS 26.6.2 | Operating-system inspection on 29 October 2026. CPU count is not a claim of eight physical cores. This was not a minimum-hardware benchmark. |
| Browser client | Local Flutter web build served at `http://127.0.0.1:8765` | The developer reported that the interactive map rendered successfully. Browser version, minimum client specification and a multi-browser compatibility matrix were not recorded. |
| Application server | Local FastAPI/Uvicorn process at `http://127.0.0.1:8001` | Supplied information to the browser while the development machine and process were running. This was not publicly hosted application infrastructure. |
| Development database and authentication | Hosted Supabase project, selected for free-tier development, with PostgreSQL/PostGIS and Supabase Auth | Hosted database connectivity, migrations and selected access checks were verified. Region, resource allocation, provider quotas and backup guarantees were not recorded as evaluated specifications. |
| Isolated database tests | `postgis/postgis:17-3.5`, managed using Docker Compose; loopback port `55432`; disposable database `floodsafe_test` | Used for destructive migration/rollback and ownership tests. The image tag describes the test service, not a verified version of the hosted Supabase database. |
| Research execution environment | Python-based modelling scripts and retained experiment metadata | Library versions and experiment configuration were recorded. Training duration, peak memory and accelerator usage were not retained as measured results. |
| External connectivity | Internet access to Supabase and OpenStreetMap tiles; research-data collection also used Open-Meteo | Online dependencies were required for those functions. No offline map packs, offline inference service or availability guarantee was demonstrated. |

No dedicated rain gauges, river-level sensors, microcontrollers or gateways were assembled. The location feature used the client device/browser’s position service. A general minimum processor, memory, bandwidth or mobile-device specification cannot yet be defended from the available measurements.

### 5.2.2 Software, Services and Configuration

**Table 5.2: Software and service configuration**

| Component | Recorded version or configuration | Implementation role and justification |
| --- | --- | --- |
| Flutter and Dart | Flutter 3.47.5; Dart 3.13.4 | Implemented the interface, asynchronous state handling, accessible controls and web build. The CI configuration records the Flutter version. |
| Application package | `0.1.0+1` in `pubspec.yaml` | Package identifier for the current source. This does not mean the previously distributed APK contains the latest connected workflows. |
| Map libraries | `flutter_map` 8.3.2; `latlong2` 0.10.1 | Rendered geographic tiles, neighbourhood markers and the device-location accuracy circle. |
| Location and networking | `geolocator` 14.1.2; `http` 1.6.0 | Requested foreground positions and parsed API responses. |
| Supabase client | `supabase_flutter` 2.18.3 | Supported email/password authentication, persisted sessions and owner-scoped saved-place operations. |
| Link handling | `url_launcher` 6.3.3 | Opened the map attribution/copyright resource. |
| Backend runtime | Python 3.13 | Executed the local API and database administration commands. |
| API framework and server | FastAPI 0.162.0; Uvicorn 0.54.0 | Exposed validated HTTP contracts and process/database health checks. |
| Database access and validation | Psycopg 3.3.6; Psycopg Pool 3.3.3; Pydantic 2.14.1 | Provided bounded database access, typed contracts and input validation. |
| Backend verification | Pytest 9.2.0; Ruff 0.17.3 | Supported automated functional/database checks and Python lint/format verification. |
| Historical modelling libraries | pandas 2.2.3; NumPy 2.1.3; scikit-learn 1.6.1; XGBoost 3.0.5; joblib 1.4.2 | Versions recorded by the model experiment, distinct from the API dependency environment. |
| Map service | OpenStreetMap standard raster tiles over HTTPS | Provided geographic context for the development preview. Attribution was included; no paid map account was configured. |
| Research weather and discharge | Open-Meteo historical/reanalysis collection scripts and manifests | Supported retrospective experiments. The app did not yet consume a live weather forecast stream. |

The tested Python dependencies were pinned in [backend/requirements.txt](../backend/requirements.txt). Flutter dependency constraints and resolved versions were recorded in [pubspec.yaml](../floodsafe/pubspec.yaml) and [pubspec.lock](../floodsafe/pubspec.lock). Historical ML versions came from the local experiment metadata and should not be assumed to be installed by the backend requirements file.

Private backend configuration was stored in ignored `backend/.env`. Flutter used ignored `floodsafe/config.local.json` for its API URL, Supabase project URL and publishable key. Database passwords and service-role/secret keys were not bundled into the application. The publishable key is a client configuration value; authenticated database access still depended on the user session and row-level security (RLS). Only placeholder configuration examples were published.

### 5.2.3 Deployment and Reproducibility

The evaluated arrangement combined a locally served application and API with a hosted development database. Deployment to Vercel or Render was discussed but was not completed as part of the evidence baseline. The application was not demonstrated as an always-available public flood-alert service.

The following procedure reproduces the connected development arrangement. Commands assume the repository root unless another directory is stated.

1. Install the recorded Flutter SDK and a compatible Python 3.13 environment. Create the backend environment and install its pinned dependencies:

   ```sh
   python3 -m venv backend/.venv
   backend/.venv/bin/python -m pip install -r backend/requirements.txt
   ```

2. If absent, create `backend/.env` from [backend/config.example.env](../backend/config.example.env). Supply the authorised Supabase session-pooler connection values locally and retain SSL mode `require`. Existing configured files must not be overwritten.

3. From `backend/`, verify the connection and apply the migrations:

   ```sh
   .venv/bin/python -m app.manage check
   .venv/bin/python -m app.manage migrate
   ```

   On an authorised **development** database, the optional seed command creates labelled sample scenarios:

   ```sh
   .venv/bin/python -m app.manage seed
   ```

   Seeding requires `FLOODSAFE_ALLOW_DEMO_DATA=true`. It is not a production-data ingestion step and does not refresh existing issue/expiry times.

4. Start the local API from `backend/`:

   ```sh
   .venv/bin/python -m uvicorn app.main:app --host 127.0.0.1 --port 8001 --no-access-log
   ```

   `GET /healthz` checks the process, while `GET /readyz` verifies database access through the restricted reader role. Interactive API documentation is available at `http://127.0.0.1:8001/docs` while the service is running.

5. Create `floodsafe/config.local.json`, if absent, from [config.example.json](../floodsafe/config.example.json). Configure `FLOODSAFE_API_URL` as `http://127.0.0.1:8001` and supply the project URL and publishable key. In Supabase Authentication → URL Configuration, use `http://127.0.0.1:8765` as the local Site URL and an allowed redirect URL. Email authentication must be enabled. Remote deployments will require their own HTTPS configuration.

6. From `floodsafe/`, install dependencies and run or build the client:

   ```sh
   flutter pub get
   flutter run -d web-server --web-hostname=127.0.0.1 --web-port=8765 --dart-define-from-file=config.local.json
   ```

   Alternatively, generate a static web build and serve it locally:

   ```sh
   flutter build web --no-wasm-dry-run --no-web-resources-cdn --dart-define-from-file=config.local.json
   python3 -m http.server 8765 --bind 127.0.0.1 --directory build/web
   ```

   These are alternative frontend launch methods; they must not compete for the same port. The local API must remain running. Real browser geolocation also requires device/browser permission and a secure context such as HTTPS or localhost.

7. From `floodsafe/`, verify the cross-runtime contract:

   ```sh
   dart run tool/check_api.dart http://127.0.0.1:8001
   ```

   The recorded check parsed four places, one current test advisory and five guide answers. Advisory and answer counts can legitimately change as publication periods expire; a later run should be interpreted against the current database state.

Reproduction requires an authorised database project, network access and the separately retained research datasets for model experiments. Cloud-synchronised files caused some local dependency/build operations to stall during development; a nonsynchronised temporary Python tooling environment was used for final backend verification. This was an environment workaround, not a measured API performance characteristic.

## 5.3 System Implementation

### 5.3.1 Implemented Modules, Integration and User Workflows

#### Database and data implementation

Four versioned SQL migrations were implemented. The migration runner used a transaction, an advisory lock and a checksum ledger to prevent silent changes to previously applied migrations. Database rollback/reapplication was tested only in the isolated test environment.

**Table 5.3: Implemented database entities and usage status**

| Entity | Purpose and relationships | Current usage boundary |
| --- | --- | --- |
| `places` | Published catalogue of named places | Four sample Nairobi neighbourhoods were seeded. |
| `profiles` | Owner-linked preferences referencing `auth.users` | RLS-protected schema existed; automatic profile provisioning and a complete preference workflow were not demonstrated. |
| `saved_places` | User-owned saved entries linked to catalogue places, with an optional default | Used by the app. Catalogue saves did not require precise GPS storage. Unique indexes prevented duplicate catalogue saves and multiple defaults per user. |
| `user_location_telemetry` | Potential timestamped user-location records | Schema existed; background collection and ingestion were not implemented. |
| `devices` | Potential user/device delivery-token records | Schema existed; push-token registration and delivery were not implemented. |
| `susceptibility_grid` | Source-attributed spatial polygons | Spatial lookup was implemented and tested with controlled geometry. Real operational polygons were not seeded. |
| `risk_assessments` | Named-place and/or zone assessments with source, model version, issue time and expiry | Development risk scenarios supported state testing. They were not live model predictions. |
| `rainfall_telemetry` | Source-attributed precipitation values with observation/forecast/reanalysis kind | Storage design existed; scheduled operational ingestion was not implemented. |
| `advisories` | Published, language-tagged general or place-specific information | A labelled English development example was seeded. |
| `assistant_answers` | Predefined questions, answers, sources, review dates, expiry and publication state | Supplied the five-question English guide; unpublished, future-reviewed and expired content was excluded by policy. |

The database therefore contained ten application tables, in addition to Supabase-managed authentication records and an internal migration ledger. A table’s existence was not treated as proof of a completed application feature.

The following non-personal example corresponds to the Kibera catalogue entry in the development seed and its public place-response fields:

```json
{"id": "kibera", "name": "Kibera", "is_demo": true}
```

The stable ID allowed selection, saved-place linkage and assessment lookup to refer to the same entry. The demonstration flag identified its sample status; the record did not establish a current flood condition. No user-account or precise personal-location sample is reproduced here.

The API read database records using `floodsafe_reader`, a role without RLS-bypass privileges, inside read-only transactions. Supabase-authenticated clients accessed their own saved-place records through owner policies based on `auth.uid()`. The atomic default-place function used invoker security and a per-user transaction lock. Authentication passwords were managed through Supabase Auth rather than stored in application tables.

Spatial matching used `ST_Covers`, which included points on polygon boundaries. Real GPS requests excluded demonstration polygons. An absent or expired assessment was not converted to low risk. These rules established consistent retrieval behaviour; they did not validate the physical accuracy of any proposed flood boundary.

#### Application modules and business rules

The application was separated into interface components, controllers and typed repositories. [DashboardController](../floodsafe/lib/dashboard/dashboard_controller.dart) managed place selection, loading, response matching, expiry and failures. A new selection cleared the previous assessment immediately, and late responses could not replace a newer selection.

**Table 5.4: Implemented application modules and traceability**

| Module | Implemented behaviour | Main evidence and related issues |
| --- | --- | --- |
| Home and preparedness | Guest access, no assumed location, clear selected-place/status/action hierarchy, persistent preparedness access, labelled test/stale/unavailable states | [Home](../floodsafe/lib/home.dart), [dashboard tests](../floodsafe/test/dashboard_controller_test.dart); #13, #23, #25 |
| API integration | Typed place, assessment, advisory and guide contracts; timezone validation; bounded requests; explicit failures | [API repository](../floodsafe/lib/data/api_repository.dart), [contract tests](../floodsafe/test/api_repository_test.dart); #8, #13 |
| Optional accounts | Email/password signup/sign-in, SDK session persistence, logout, explicit browser-origin confirmation redirect | [Account repository](../floodsafe/lib/account/account_repository.dart), [account screen](../floodsafe/lib/account/account_screen.dart), [redirect test](../floodsafe/test/auth_redirect_test.dart); partial #11 |
| Saved places | Save/remove supported places, set a default, restore it on return, clear account-specific state on sign-out | [Account tests](../floodsafe/test/account_test.dart), saved-place migration and RLS tests; #6–#8, #11, #13 |
| Foreground location | One requested position, permission/failure handling, recency and accuracy checks, manual fallback | [Location service](../floodsafe/lib/location/location_service.dart), [location tests](../floodsafe/test/location_service_test.dart); partial #12 |
| Interactive map | Geographic tiles, approximate neighbourhood centres, saved-place bookmarks, GPS marker/accuracy circle, zoom/recentre controls, text selection and tile retry | [Map screen](../floodsafe/lib/maps/map_screen.dart), [map tests](../floodsafe/test/map_test.dart); #13, partial #22 |
| Guided assistant | Selectable published questions, database responses, source/review dates, retries, duplicate-request prevention and expiry handling | [Guide screen](../floodsafe/lib/assistant_screen.dart), [guide tests](../floodsafe/test/assistant_test.dart); partial #16–#20, #24 |
| Development verification | Python/Flutter checks and reproducible isolated database setup | [CI workflow](../.github/workflows/checks.yml), [database tests](../backend/tests/test_database.py); partial #29 |

Location fixes older than two minutes, more than 30 seconds in the future, worse than 250 metres in reported accuracy, or with invalid coordinates were rejected. The service requested a fix with a 15-second limit. These were implemented application checks, not experimentally justified proof of adequate emergency-location accuracy.

In connected mode, coordinates were sent transiently in the dashboard POST body. They were not placed in request URLs or persisted by that flow. The map rendered device coordinates separately from approximate neighbourhood reference points. No reverse-geocoding request was made. Tile requests disclosed the viewed map area to the tile provider, as expected for the external map connection.

The guide used deterministic retrieval rather than a generative language model. Users could select only listed questions; there was no arbitrary chat-message endpoint or saved conversation history. Its initial content explained application use and limitations. It was not a clinically or locally certified emergency-advice service, and it did not calculate routes or current flood conditions.

The illustrative map entry point was replaced by an interactive map, while sample Flood News was hidden. Open-Meteo-supported weather updates remained a proposed integration. English was the implemented content language; an `en/sw` schema option did not establish completed Kiswahili support.

#### Interfaces and integration boundaries

The implemented information API exposed:

- `GET /v1/places` for the published place catalogue.
- `POST /v1/dashboard` for a named-place or transient GPS assessment lookup.
- `GET /v1/advisories` for current published information.
- `GET /v1/assistant/questions` for the guide catalogue.
- `GET /v1/assistant/questions/{id}` for a selected answer.
- `GET /healthz` and `GET /readyz` for process and database checks.

The browser used two distinct connections: FastAPI for public information and Supabase Auth/Data API for authenticated saved-place operations. No custom FastAPI user-write, model-inference, SMS, push-delivery or evacuation-routing endpoint was completed. API errors did not trigger an automatic switch to sample risk data.

#### Representative end-to-end workflows

**Guest information lookup:** The user opened Home, selected a supported place, and initiated an assessment request. The controller cleared the previous result, the API validated the request, the repository read permitted records and the interface displayed either the assessment with provenance or an explicit unavailable/stale/error state. Preparedness guidance remained accessible throughout the workflow.

**Saved-place return:** A signed-in user saved a catalogue place and optionally made it the default. The database associated it with the authenticated owner. A restored session could load that default unless a manual selection had already superseded it. Sign-out invalidated pending location/default requests and cleared account-specific displayed state. Automated tests demonstrated these behaviours with injected account services; a full real-account lifecycle and cross-device evaluation were not established.

**Map-to-Home lookup:** The user opened the map, selected a neighbourhood/bookmark or requested a foreground device position, and chose “View information on Home.” The selected place was returned to the existing assessment flow. Map markers did not assign a risk score, identify safe destinations or imply current coverage by a flood model.

**Guided help:** The user selected a published question. The API retrieved its currently published answer, which was displayed with source and review metadata. Loading, failure and expiry states did not produce invented replacement text. Long publication periods were checked through bounded timers to avoid browser timer overflow.

### 5.3.2 Data and Model Implementation for AI/ML

#### Dataset description and provenance

The research pipeline used historical modelled river discharge and reconstructed rainfall associated with five provisional GloFAS cells. Retained manifests and collection scripts supported source and request traceability. These grid cells were research locations and were not the same entities as the four neighbourhoods in the application’s demonstration catalogue.

**Table 5.5: Recorded research data and partitions**

| Item | Recorded value | Evidence and interpretation |
| --- | --- | --- |
| Discharge-history period | 1 January 2010–31 December 2024 | Local `river_history/history_summary.json`. |
| Research cells | 5 | Provisional model-cell/river identity required further validation. |
| Raw discharge rows | 27,395 | One cell-day record; history metadata reported zero missing discharge values. This was not a complete audit of every input variable. |
| Training period and usable rows | 2010–2018; 16,400 | Local experiment metadata, after lag-window preparation. |
| Validation period and usable rows | 2019–2021; 5,480 | Used during model development and error analysis. |
| Reserved final test period and usable rows | 2022–2024; 5,480 | Metadata explicitly recorded `test_evaluated: false`. No final test metrics are claimed here. |
| Total usable rows | 27,360 | Training, validation and reserved rows combined. |
| Rows excluded by initial feature windows | 35 | Seven initial records per cell were excluded by lag/rolling requirements. |
| Rainfall source configuration | Open-Meteo historical ERA5 daily `precipitation_sum`, GMT, 2010–2024 | Local weather request manifest recorded the source parameters and SHA-256 checksums. Rainfall was sampled at model-cell locations, not aggregated over verified upstream catchments. |
| Target | Simulated discharge above the cell-specific training-period 95th percentile | Binary high-flow proxy, not an independently observed flood label. |
| Base experiment input count | 17 | Lagged/rolling discharge ratios, lagged rainfall totals, flow change, season terms and cell indicators. |
| Record-level privacy | Environmental cell-day records | These modelling inputs were not app-user GPS histories. Dataset ownership, source licences and redistribution conditions still require a complete report record. |

The original labelled dataset was identified in experiment metadata by SHA-256 `4b44f4d56ce2fcc96801c188ac959937f6c4183fc86467ad1c51b23805aec1a4`. The private/local research inputs and generated reports were excluded from version control. Their aggregate results are reported below with explicit provenance; a repository clone alone is insufficient to reproduce the model experiments.

#### Data preparation and partitioning

The training script joined discharge and rainfall by cell and date with a one-to-one merge check and sorted observations chronologically. Each cell’s high-flow threshold was computed from training-period discharge only. Inputs included discharge lags of 1, 2, 3 and 7 days; prior 3- and 7-day discharge means; previous 1-, 3- and 7-day rainfall totals; lagged flow change; seasonal sine/cosine values; and cell indicators.

Rolling inputs were shifted so that target-day observations were not included in the corresponding prior-day windows. Initial rows without complete windows were removed. The script checked selected lag/rainfall windows against the original series and asserted that training dates preceded validation dates. Learned scaling in the logistic-regression pipeline was fitted during training.

The split was chronological rather than random. Nevertheless, the same cells appeared in different time partitions, adjacent days remained correlated, and retrospective reconstructed inputs were not shown to have been available at operational issue time. The split therefore did not establish geographic generalisation or a real-time warning capability.

A later input comparison selected candidates using 2019–2020 results and examined 2021 again. Its metadata acknowledged that 2021 had already appeared in the earlier validation report. It cannot be presented as a new untouched holdout. The final 2022–2024 period remained outside the reported model evaluation.

#### Model training and selection

The base experiment compared two simple baselines with three learned candidates. Models used a fixed random seed of 42 where applicable. The saved candidate artefacts included feature order, per-cell thresholds, the decision threshold, target description and research-status limitation.

**Table 5.6: Base experiment configuration**

| Model or baseline | Recorded configuration | Purpose |
| --- | --- | --- |
| Always low | Predicted the negative class for all validation records | Showed the consequences of never issuing a high-flow classification. |
| Persistence | Repeated the previous day’s high-flow class; used previous flow/training threshold for ranking metrics | Provided a meaningful baseline for temporally persistent discharge. |
| Logistic regression | Training-fitted standardisation; balanced class weights; `max_iter=2000`; seed 42 | Provided a relatively interpretable learned comparison. |
| Random forest | 250 trees; maximum depth 10; minimum leaf size 10; balanced-subsample weights; seed 42; two workers | Represented nonlinear tree-based classification. |
| XGBoost | 250 estimators; depth 3; learning rate 0.05; subsample and column sample 0.8; L2 term 5; training imbalance weighting; seed 42; two workers | Represented boosted-tree classification. |

The original learned candidates were evaluated at score threshold 0.5. The 95th-percentile discharge **label threshold** and the model’s **decision threshold** served different purposes and must not be confused.

Additional scripts examined class weighting, input groups, threshold choices, false alarms, onset detection and hypothetical delayed inputs. The input-comparison summary identified `logistic_regression__flow_only` as a provisional candidate at decision threshold 0.95 under a 2019–2020 daily-F1 selection rule. The flow-only group retained season and cell identity. The class-weight experiment selected no overall winner, and the alert-limit analysis recorded that no operating limit or final model had been approved.

No final production model was selected in this chapter. The experimental classifier had not been exposed through the application API, scheduled for inference or converted into validated application severity categories.

## 5.4 Testing and Evaluation

### 5.4.1 Test Strategy and Acceptance Criteria

Application verification combined component/state tests, widget tests, HTTP contract checks, database integration tests and selected live development checks. Positive, negative, boundary and asynchronous failure cases were used. The database test suite was restricted to a disposable local PostGIS service and checked a test-only marker before destructive operations; it did not use the hosted Supabase database.

The main functional acceptance conditions were that a response belonged to the selected place, missing/stale data was represented honestly, only permitted records were accessible, account changes did not retain another account’s state, and guide/map failures preserved a usable alternative. Accessibility checks examined labels, touch targets and enlarged-text layouts. These conditions were implemented in test assertions; they were not substitutes for a formal field or usability evaluation.

The latest recorded local verification on 28 October 2026 produced:

- **51 passing Flutter tests**, covering state, contracts, account flows, location, guide and map behaviours.
- **24 passing Python/API/database tests**, including migration, access-control and spatial cases.
- Successful Flutter analysis, Dart formatting, Ruff lint/format checks and a connected web build.
- A completed, successful GitHub Actions “Project checks” run, [run #1](https://github.com/princessimelda/AutomatedFloodAlert/actions/runs/40754772224), associated with the application commit; its recorded status was inspected on 29 October 2026.
- A successful Dart-to-API-to-Supabase contract check for four places, one then-current advisory and five guide answers.
- A successful representative Nairobi tile request and local preview response, both HTTP 200.

These are the recorded development execution results, not a claim that tests were rerun on 29 October to prepare this README. Full console logs were not committed as a permanent evidence bundle. The repeatable commands and source tests provide a basis for an assessor to regenerate logs against the same revision and controlled conditions.

From `floodsafe/`, the application checks were:

```sh
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
flutter build web --no-wasm-dry-run --no-web-resources-cdn --dart-define-from-file=config.local.json
```

For database verification, the isolated service was started from the repository root:

```sh
docker compose -p floodsafe-db-tests -f backend/compose.test.yml up -d
```

From `backend/`, the checks were:

```sh
PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 FLOODSAFE_RUN_DB_TESTS=1 .venv/bin/python -m pytest -q
.venv/bin/ruff check app tests
.venv/bin/ruff format --check app tests
```

The isolated suite must not be redirected to Supabase. Without the explicit database-test flag, database cases are skipped; a skipped run must not be reported as a complete database pass. A Starlette/httpx TestClient deprecation warning was observed, although the recorded tests passed.

### 5.4.2 Test Cases, Defects and Retesting

**Table 5.7: Selected repeatable application and database test cases**

| Test ID | Traceability | Scenario and conditions | Expected result | Recorded outcome, evidence and verdict |
| --- | --- | --- | --- | --- |
| TC-01 | #13 / Home | Open the app without an account or selected location | No location or low-risk status assumed; guidance accessible | Passed in [widget tests](../floodsafe/test/widget_test.dart). |
| TC-02 | #13 / asynchronous state | Select another place while an earlier request remains outstanding | Old risk cleared and late earlier response ignored | Passed in [controller tests](../floodsafe/test/dashboard_controller_test.dart). |
| TC-03 | #8, #13 / contract and freshness | Supply mismatched IDs, missing timezones, future/expired assessments or request timeout | Invalid responses rejected; stale, unavailable and error states remain distinct | Passed in API repository and controller tests. |
| TC-04 | #12 / location | Deny permission, disable location, return stale/inaccurate coordinates or time out | Explicit failure and manual selection remain available | Passed with fake platform/service inputs in [location tests](../floodsafe/test/location_service_test.dart) and widget tests; physical-device coverage remained pending. |
| TC-05 | #7, #8 / ownership | Act as user A and attempt to access or write user B’s records | RLS prevents unauthorised reads/writes | Passed in [isolated database tests](../backend/tests/test_database.py); not a complete security audit. |
| TC-06 | #11, #13 / saved places | Save/remove a place, change the default, restore a session and sign out | At most one default; correct restoration; account-specific state cleared | Passed in account tests and owner/default database tests; full real-account lifecycle testing remained incomplete. |
| TC-07 | #11 / confirmation redirect | Inspect signup request and probe local redirect configuration | Signup requests the browser origin; configured verification responses return to the preview | Mocked request regression passed. Live invalid-token probe returned HTTP 303 to the local preview; this alone did not prove a fresh successful confirmation round trip. |
| TC-08 | #16–#18 / guided retrieval | Request known, unknown, draft, future-reviewed or expired content; attempt arbitrary chat | Only published/current answers returned; unsupported requests rejected | Passed in API, RLS and guide tests. |
| TC-09 | #18, #20 / expiry regression | Display a 90-day answer across bounded checks, then advance to its actual expiry | Valid answer remains visible until due, then disappears | Passed in [guide regression test](../floodsafe/test/assistant_test.dart). |
| TC-10 | #13, #22 / map and GPS | Select a neighbourhood/saved marker or obtain a controlled device fix | Geographic selection and metre-based accuracy circle; no inferred flood boundary | Passed in [map tests](../floodsafe/test/map_test.dart) with local image tiles. Informal browser rendering was also confirmed by the developer. |
| TC-11 | #25 / accessibility | Use a narrow 320 × 640 viewport with 200% text scaling and labelled controls | Tested flows render without overflow; Home label/touch-target checks pass | Passed in relevant widget/map/guide tests. No general WCAG-conformance verdict was assigned. |
| TC-12 | #7, #14 / spatial boundaries | Match controlled polygons, boundary points, overlaps and demo zones | Boundary inclusion, severity ordering and exclusion of demo geometry for real GPS | Passed in isolated PostGIS tests. No verified evacuation route was generated. |
| TC-13 | #7 / migration integrity | Apply migrations/seeds again and roll back/reapply in the disposable database | Consistent schema; checksum enforcement; original seed validity retained | Passed in database tests. Destructive verification remained isolated. |
| TC-14 | #8 / outage and CORS | Fail the database; use disallowed origins or invalid API operations | Controlled errors; no silent fixture fallback; exact allowed origins | Passed in [API tests](../backend/tests/test_api.py). |

The test IDs above organise this draft’s evidence. They should be mapped to the final Chapter 4 requirement IDs rather than presented as pre-existing approved identifiers.

**Table 5.8: Observed defects, corrections and retesting**

| Defect | Observed behaviour | Correction | Retest evidence and remaining boundary |
| --- | --- | --- | --- |
| Confirmation destination mismatch | The user confirmed an email address but the destination page failed | Supabase local Site URL/allowlist was configured and web signup explicitly requested the current origin | Redirect-request regression passed; a live probe reached the local preview. The user’s confirmation and the redirect configuration checks were distinct evidence items. |
| Guide expiry timer overflow | Valid answers were returned by the API but hidden by the app’s long-delay timer | Replaced the full publication-period timer with bounded validity rechecks | Seven guide tests passed, including the long-lived-answer regression; all five answers passed the live contract check and the web build succeeded. |
| Isolated rollback dependency | Reapplying the core/default migrations encountered an already-existing default-place function | Executed the default-place rollback before the core rollback in the isolated test | All 24 backend/database tests subsequently passed. No hosted rollback was used. |
| Map test fixture and gesture assumptions | Initial map tests used an invalid image fixture and attempted scrolling through a map-pan gesture surface | Replaced the local tile fixture and used controlled scroll-position changes in the test harness | The map suite and subsequent full Flutter suite passed. This was a test-harness correction, not evidence of a failed live tile provider. |

### 5.4.3 Project-Type-Specific Evaluation

#### Application and human-centred evaluation

Application evidence established deterministic behaviour under the tested conditions. It did not establish production throughput, uptime, phone compatibility, field reliability, formal accessibility conformance or usability across Nairobi residents. Developer feedback confirmed that the map worked in a browser. This was one informal demonstration report, not a recruited user study with recorded participants, task completion rates or time measurements.

The supervisor’s feedback prioritised an interface in which users could quickly understand what to do. The resulting implementation provided a location–situation–action reading order, labelled controls, guest access and persistent preparedness guidance. Automated layout checks supported these design decisions, but no claim that they improved user task performance can yet be made without an appropriate evaluation.

#### Model evaluation

The base model experiment evaluated **5,480 validation cell-days from 2019–2021**, including **535 positive high-flow days, 4,945 negative days and 70 within-cell high-flow onsets**. The results below were transcribed from the retained local `validation_metrics.csv`; they were not newly generated for this chapter.

**Table 5.9: Base experiment validation metrics, rounded to four decimal places**

| Candidate | Precision | Recall | F1 | ROC-AUC | Average precision |
| --- | ---: | ---: | ---: | ---: | ---: |
| Always low | 0.0000 | 0.0000 | 0.0000 | 0.5000 | 0.0976 |
| Persistence | 0.8692 | 0.8692 | 0.8692 | 0.9857 | 0.9397 |
| Logistic regression | 0.6728 | 0.9570 | 0.7901 | 0.9868 | 0.9465 |
| Random forest | 0.8127 | 0.9084 | 0.8579 | 0.9847 | 0.9399 |
| XGBoost | 0.7673 | 0.9308 | 0.8412 | 0.9875 | 0.9456 |

The learned candidates used score threshold 0.5. Persistence classification repeated the previous-day class; its ranking metrics used the continuous previous-flow/training-threshold ratio. Average precision is reported by its actual metric name; it is not relabelled as a differently calculated PR-AUC measure.

**Table 5.10: Validation errors and onset detection for the same base experiment**

| Candidate | False-positive days | False-negative days | True-positive days | Detected onsets / 70 | Onset recall |
| --- | ---: | ---: | ---: | ---: | ---: |
| Always low | 0 | 535 | 0 | 0 | 0.0000 |
| Persistence | 70 | 70 | 465 | 0 | 0.0000 |
| Logistic regression | 249 | 23 | 512 | 47 | 0.6714 |
| Random forest | 112 | 49 | 486 | 21 | 0.3000 |
| XGBoost | 151 | 37 | 498 | 35 | 0.5000 |

A high-flow onset was a positive target day preceded by a negative target day within a model cell. These onsets were not independently verified flood incidents. Class days and episodes were correlated, so the counts must not be interpreted as independent field-event detection statistics.

The results showed why daily classification and first-day detection required separate interpretation. Persistence had the highest daily F1 in this base comparison but detected none of the defined onsets. Logistic regression detected more onsets and missed fewer positive days, while producing more false-positive days. Random forest and XGBoost exhibited different trade-offs. These findings supported further investigation; they did not establish a selected live-warning model or guaranteed useful warning lead time.

#### Performance, reliability and security evaluation boundary

Configured timeouts, pool limits and statement limits were implementation controls rather than measured performance results. No latency percentile, concurrent-user capacity, SMS delivery rate, notification success rate, energy-use result or availability percentage was established. RLS and negative-input tests supported specific authorisation and integrity claims, but did not constitute a penetration test, comprehensive threat assessment or assurance of the complete hosted identity lifecycle.

### 5.4.4 Results Presentation and Interpretation

The chapter used tables to distinguish exact counts, configuration and observed outcomes. Application pass counts described automated assertions; the model tables described retrospective validation classification. Neither type of result substituted for the other.

Some earlier component README files retained historical test counts and descriptions from intermediate increments. This draft used the latest recorded aggregate application counts and the current source at the stated baseline. Those earlier figures should be read as historical checkpoints, not contradictory claims about a new run.

Final held-out model results, independent flood labels, repeated-run uncertainty, fully reproduced experiment logs, wider user feedback and device/browser compatibility results were not available in the evaluated evidence set. These absences constrain the conclusions that can be drawn from the implementation.

## 5.5 Version Control and Implementation Evidence

[Project repository](https://github.com/princessimelda/AutomatedFloodAlert) contains the implementation source and development history. The connected-workflow changes were pushed on [feature/13-home-core](https://github.com/princessimelda/AutomatedFloodAlert/tree/feature/13-home-core) and integrated through [pull request #31](https://github.com/princessimelda/AutomatedFloodAlert/pull/31). GitHub metadata inspected on 29 October 2026 confirmed that the PR was merged into `main` on 28 October 2026, producing merge commit [`156546f7`](https://github.com/princessimelda/AutomatedFloodAlert/commit/156546f7c6e262686e460e57554b8f097adff144). The local application-source baseline used for this draft was the PR head, `e60edd5`.

The class conventions were applied: `category/issue-number-short-description` for branches and `type(scope): imperative description` for commit headers under 50 characters. Two commits captured the connected implementation:

- [`8057174`](https://github.com/princessimelda/AutomatedFloodAlert/commit/8057174): `feat(api): add Supabase-backed core services`.
- [`e60edd5`](https://github.com/princessimelda/AutomatedFloodAlert/commit/e60edd5): `feat(app): connect accounts, guide and maps`.

The commits referenced related issues without automatically closing parent work whose full criteria were incomplete. The PR contained two commits and was recorded as merged, rather than merely proposed. The merge record does not by itself demonstrate independent peer review or supervisor approval. The CI workflow was configured for pull requests and pushes to `main`. The PR-head workflow [Project checks, run #1](https://github.com/princessimelda/AutomatedFloodAlert/actions/runs/40754772224) was recorded as completed with a successful conclusion; this was checked separately from the local test results. This automated outcome does not establish completion of every research or field-evaluation requirement.

**Table 5.11: Evidence register**

| Evidence ID | Artefact | Supports | Availability and limitation |
| --- | --- | --- | --- |
| E-01 | [Application source](../floodsafe/lib/) and [tests](../floodsafe/test/) | Implemented interface, state, account, guide, location and map logic | Repository source; test definitions must be accompanied by regenerated/retained execution logs for formal assessment. |
| E-02 | [Backend source](../backend/app/) and [tests](../backend/tests/) | HTTP validation, reader-role access and controlled failures | Repository source; latest recorded local run had 24 passes. |
| E-03 | [Migrations](../supabase/migrations/), [rollback scripts](../supabase/rollbacks/) and [development seed](../supabase/seed.sql) | Database structure, owner policies, publication state and repeatability | Repository artefacts. Destructive testing was limited to the disposable database. |
| E-04 | [Dependency lockfiles](../floodsafe/pubspec.lock), [Python pins](../backend/requirements.txt) and [Compose configuration](../backend/compose.test.yml) | Environment reproduction | Research-library versions are separately recorded in experiment metadata. |
| E-05 | [Dart contract checker](../floodsafe/tool/check_api.dart) | Cross-runtime application/API parsing | Recorded live check covered four places, one then-valid advisory and five guide answers. |
| E-06 | Local `data/processed/high_flow_models/experiment_metadata.json` and `validation_metrics.csv` | Dataset sizes, configuration, software versions and Tables 5.9–5.10 | Inspected during drafting; generated research artefacts are excluded from Git. A permitted evidence package remains necessary for independent reproduction. |
| E-07 | Local `data/processed/river_history/history_summary.json` and `data/raw/model_weather/manifest.json` | Source parameters, period, counts and checksums | Local research provenance, not published raw user data. |
| E-08 | Local input/weight/error/alert-limit experiment summaries | Candidate-selection and evaluation caveats | Validation exploration; no approved operating threshold or final-test result. |
| E-09 | [CI workflow](../.github/workflows/checks.yml), [successful run #1](https://github.com/princessimelda/AutomatedFloodAlert/actions/runs/40754772224), [merged PR #31](https://github.com/princessimelda/AutomatedFloodAlert/pull/31) and linked commits | Automated-check results and version history | Remote completion/success and PR merge were verified on 29 October 2026; neither establishes independent user or field validation. |
| E-10 | Recorded development checks and user feedback on 28 October 2026 | Auth service connectivity, redirect configuration, tile delivery and informal map rendering | Development evidence; no fabricated console transcript, screenshot or formal participant study is supplied. |

Private configuration, credentials, environments, large local datasets and generated web builds were excluded from version control. The repository’s licence and the permissions required to redistribute each dataset/model dependency should be confirmed before a public research-data release; public source availability alone does not establish unrestricted redistribution rights.

## 5.6 Author Oversight and Use of AI-Assisted Tools

OpenAI Codex, provided by OpenAI, assisted with application/backend implementation, debugging, test preparation, code review, documentation and drafting this Chapter 5 README. The assistance extended beyond spelling or language editing and is disclosed accordingly.

Implementation suggestions were checked through source inspection, automated tests, lint/format checks, builds and selected live development probes. The developer supplied requirements and design priorities, configured the authorised Supabase project, tested the application and reported map behaviour. The supervisor’s reported feedback about intuitive use and accessibility informed the interface direction; no supervisor approval of the completed system or this chapter is implied.

For this draft, the assistant inspected the supplied writing guide, implementation source, dependency records and local research metadata/results. No model training, new held-out test evaluation, participant recruitment or fabricated measurement was used to fill missing results. The student must review the text, verify its evidence, reconcile it with the approved Chapters 1–4, and accept responsibility for the material retained in the submitted report.

**Table 5.12: Summary AI-assistance record**

| Date | Assistance | Verification and author oversight |
| --- | --- | --- |
| 28 October 2026 | Connected application/database workflows; account and guide debugging; interactive map; tests and setup documentation | Automated checks, live service probes, source review and developer feedback. Real-device and formal user evaluation remained incomplete. |
| 29 October 2026 | Chapter 5 structure, evidence compilation, interpretation and writing | Compared the supplied guide with repository source and retained experiment artefacts; unsupported outcomes were identified as unavailable. Final student/supervisor review remained outstanding. |

This declaration records the actual assistance known at drafting time. It does not assert that an institutional AI-use declaration or supervisor review has already been completed.

## 5.7 Evaluation Results, Discussion and Limitations

### 5.7.1 Evaluation Against the Implemented Work Areas

**Table 5.13: Implementation outputs, evidence and supported interpretation**

| Work area | Implemented output and acceptance condition | Observed evidence | Interpretation and remaining boundary |
| --- | --- | --- | --- |
| Connected flood-information application | Correct selected-place response; clear unavailable/stale states; accessible guidance | Typed contracts, controller/widget tests, live Dart/API/database check | Supported the connected information workflow. It did not establish current flood predictions or full bilingual requirements. |
| User continuity and privacy | User-owned saved places, a single default and removal of account-specific state at sign-out | Account widget tests and isolated owner/default tests | Supported the implemented ownership rules. Complete hosted account recovery, deletion, cross-device and native lifecycle verification remained incomplete. |
| Geographic interaction | Geographic tiles, distinct neighbourhood/GPS markers, accuracy display and selection back to Home | Map tests, HTTP tile check and informal user confirmation | Supported map interaction and geographic context. Markers were not flood boundaries, shelters or routing evidence. |
| Guided assistance | Only published/current predefined answers; source metadata and recoverable failures | Guide/API/RLS tests and the expiry regression | Supported a constrained English app-help service. It did not establish generative reasoning, locally reviewed emergency knowledge or bilingual answer accuracy. |
| Model investigation | Reproducible retrospective comparisons against simple baselines | Local metadata, validation metrics and error/threshold summaries | Demonstrated measurable differences in daily classification and onset behaviour. It did not establish performance on verified floods or the reserved final test period. |
| Operational warning capability | Timely model output integrated with valid geographic risk and delivery | No completed prediction-to-alert chain in the evaluated baseline | Remained unestablished. Application state handling and model validation alone could not substantiate operational warnings. |

Formal objective-level attainment cannot be assigned solely from these implementation categories. The final chapter must preserve the approved research questions and objective wording and relate each to the evidence actually obtained.

### 5.7.2 Discussion of the Main Findings

The implementation demonstrated that the interface, information API and hosted data store could be connected while maintaining visible data-validity boundaries. Guest access and manual selection kept preparedness information available without requiring an account or a location fix. Sources and timestamps made the origin and currency of displayed records inspectable, although their presence did not itself validate the underlying flood information.

The account and map work improved the completeness of the demonstration journey: an area could be selected geographically, saved under an authenticated owner and revisited through a default. This was an implementation outcome rather than evidence of quantified usability improvement. The available informal browser feedback supported continued use of the map, but did not represent the intended user population.

The guide defect illustrated the difference between backend availability and correct client presentation. Successful retrieval did not ensure a visible answer when a browser timer incorrectly triggered expiry. The correction and regression test addressed that mechanism. Similarly, successful email confirmation and successful navigation back to the app were separate events; both had to be considered when evaluating the account workflow.

The model comparison showed that a strong persistence baseline was necessary. A high daily F1 did not establish useful first-day warning behaviour. Logistic regression improved the reported onset-detection count relative to persistence but generated substantially more false-positive days. The operational consequences of missed onsets and false alarms therefore could not be reduced to a single headline score. Later validation exploration did not remove the need for a frozen selection rule and independent final evaluation.

### 5.7.3 Limitations Affecting Interpretation

1. **Proxy labels:** High flow was derived from simulated discharge and a training-period quantile. Verified observed flood outcomes were not the basis of the reported classifier results.
2. **Retrospective input availability:** Reconstructed flow and rainfall were not shown to be available when a real warning would have to be issued. Stress tests with shifted inputs represented hypothetical delays, not measured provider latency.
3. **Spatial representativeness:** Five provisional cells and point rainfall did not establish full Nairobi catchment coverage. Cell 02’s low-flow behaviour remained unresolved, and the relationship between research cells and neighbourhood-level user risk was not validated.
4. **Temporal dependence and selection:** Correlated cell-days, repeated validation exploration and no independent 2021 holdout constrained generalisation claims. The reserved 2022–2024 period remained unevaluated.
5. **Unfinished model-to-app integration:** The app used labelled development assessments. Binary high-flow scores were not mapped to validated low/moderate/high user-facing categories, and there was no operational inference schedule.
6. **Geographic interpretation:** Neighbourhood coordinates were approximate reference points. Validated flood polygons, blocked-road data, verified destinations and safe evacuation routes were absent.
7. **Knowledge and language coverage:** The guide covered five English app-help questions. Local safety-content review, comprehensive answer evaluation and Kiswahili implementation were incomplete.
8. **Identity and privacy lifecycle:** Selected RLS and session behaviours were tested, but password recovery, account deletion and native confirmation-link handling remained unfinished. Location/device tables did not imply implemented consented telemetry or retention jobs.
9. **Evaluation population and devices:** No formal usability study, participant sample, disability-inclusive evaluation, complete keyboard/screen-reader review or representative physical-device matrix was completed.
10. **Service and deployment conditions:** The app/API remained locally hosted, with external Supabase and tile-service dependencies. Public hosting, uptime, capacity, recovery, backups and provider quotas were not evaluated as production commitments.
11. **Performance and delivery:** There were no measured end-to-end alert latencies, load limits, SMS/push delivery outcomes or operational notification reliability results.
12. **Evidence portability:** Raw research inputs, aggregate reports and historical console logs were not all available in the Git repository. Dependency records and source tests aided reproduction, but a complete permitted assessment evidence package and documented data licences were still required.

These limitations define what the current evidence supports. Final conclusions, stakeholder recommendations and proposed research extensions belong in Chapter 6 and are not presented here as completed findings.
