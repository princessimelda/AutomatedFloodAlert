# Render deployment

Prepared 25 November 2026. This guide hosts the Flutter web app and FastAPI
backend on Render, retaining Supabase PostgreSQL/Auth and the existing GitHub
weather worker. SMS and its delivery loop remain disabled. Hosting is not complete
until the public acceptance checks below pass.

## Services and budget

- `floodsafe-api`: Docker web service, 0.5 CPU / 512 MB, one instance, Frankfurt.
  Estimated base compute: US$7/month; check Render's displayed price before creation.
- `floodsafe-web`: static site, no paid compute instance.
- Keep the Hobby workspace; a paid workspace upgrade is not required just to run
  a paid compute service. Included bandwidth/build limits, taxes and overages apply.
- Keep Supabase and the weather worker in place. No Render database, disk,
  separate background worker or cron service is needed for this release.

The root [Blueprint](../render.yaml) records both services. For the first
deployment, create them in the following order so their actual public addresses
can be configured without guessing an `onrender.com` hostname.

## 1. Create the API

In Render choose **New → Web Service** and select
`princessimelda/AutomatedFloodAlert` after the deployment PR has been merged.

| Setting | Value |
| --- | --- |
| Branch | `main` |
| Name | `floodsafe-api` (or another available name) |
| Root directory | `backend` |
| Runtime | Docker |
| Dockerfile | `./Dockerfile` |
| Docker context | `.` |
| Region | Frankfurt |
| Instance | 0.5 CPU / 512 MB paid instance; confirm displayed price |
| Health check | `/readyz` |
| Instances | 1 |
| Auto deploy | After CI checks pass |

Supply these **only to the API service**, using the existing private files:

On the working machine, ignored `backend/.env.render` has been prepared for the
API's **Add from .env** input. It contains only the required server settings,
with SMS disabled and CORS initially empty. Keep it private and import it only
into the API service, never the static site or a GitHub issue. This local export
is not present in a fresh checkout; the table below remains the source mapping.

| Variable | Value/source |
| --- | --- |
| `FLOODSAFE_DATA_MODE` | `postgres` |
| `FLOODSAFE_ALLOW_DEMO_DATA` | `true` (retains explicitly labelled catalogue/demo scenarios) |
| `FLOODSAFE_DB_HOST` | Existing `backend/.env` host |
| `FLOODSAFE_DB_PORT` | `5432` |
| `FLOODSAFE_DB_NAME` | Existing database name, normally `postgres` |
| `FLOODSAFE_DB_USER` | Existing `backend/.env` user |
| `FLOODSAFE_DB_PASSWORD` | Existing private database password |
| `FLOODSAFE_DB_SSLMODE` | `require` |
| `FLOODSAFE_AUTH_URL` | Existing `backend/.env.notifications` value |
| `FLOODSAFE_AUTH_PUBLISHABLE_KEY` | Existing public Auth key |
| `FLOODSAFE_ALERT_PRINCIPALS` | Existing private generated JSON role mapping |
| `FLOODSAFE_CORS_ORIGINS` | `[]` until the web service has an actual public URL |
| `FLOODSAFE_SMS_ENABLED` | `false` |
| `FLOODSAFE_NOTIFICATION_WORKER_ENABLED` | `false` |

Do not upload `.env.notifications` wholesale: Twilio credentials are not needed.
Do not place DB passwords, role keys or Supabase service-role keys on the static
site. The Docker build copies only requirements and application code; private
configuration is supplied at runtime. Render provides `PORT` automatically.

Create the API, then record its actual HTTPS URL. `/healthz` checks the process;
`/readyz` must return ready and verifies database/schema access. A failing health
check is a deployment failure, not a reason to enable fixture fallback or run
destructive database tests against Supabase. Existing migrations are already
applied to the current development database; do not reseed expired scenarios.

## 2. Create the Flutter static site

Choose **New → Static Site**, using the same repository and `main` branch.

| Setting | Value |
| --- | --- |
| Name | `floodsafe-web` (or another available name) |
| Root directory | Leave empty (repository root) |
| Build command | `python3 scripts/build_render_web.py` |
| Publish directory | `floodsafe/build/web` |
| Auto deploy | After CI checks pass |

Set these three public build variables:

- `FLOODSAFE_API_URL`: the actual HTTPS API origin from step 1, without `/v1`.
- `FLOODSAFE_SUPABASE_URL`: the existing Supabase project HTTPS origin.
- `FLOODSAFE_SUPABASE_PUBLISHABLE_KEY`: existing `sb_publishable_...` key.

These are intentionally visible in the browser bundle. The build script validates
them and passes only those three values to Flutter, never the entire environment
or the local configuration file. It installs Flutter 3.47.5, matching CI, and
bundles web renderer resources. Build failures must be corrected before launch.

Add the rewrite `/*` → `/index.html` (action **Rewrite**). Existing asset files
are served normally. Set `Cache-Control: no-cache` for `/index.html` and
`/flutter_bootstrap.js`; the Blueprint also specifies `X-Content-Type-Options:
nosniff` for all paths. Changing public build variables requires a rebuild.

## 3. Align origins and email confirmation

Once Render allocates the actual web URL:

1. On the API set `FLOODSAFE_CORS_ORIGINS` to a JSON list containing that exact
   origin, for example `["https://actual-web-name.onrender.com"]`. Save/redeploy.
   Do not use a wildcard. Local preview origins can be added explicitly if needed.
2. In Supabase **Authentication → URL Configuration**, set Site URL to the web
   origin and add the same URL to Redirect URLs. Retain loopback redirects only
   if local development still needs them.
3. Confirm the static build uses the correct API URL and public Auth settings.
   The app derives its email confirmation redirect from the browser origin.
4. Request a fresh confirmation email for testing; older links may retain the
   previous redirect. Keep server role keys out of screenshots and browser code.

## Acceptance and recovery

- Both public services are live; API `/readyz` returns ready.
- Browser requests work with the exact CORS origin and no mixed HTTP content.
- Register/confirm email, sign in, reload to restore session and sign out.
- Save a place and verify it returns after signing back in; test account isolation.
- Check named places, the map, location consent/denial and guided answers.
- Publish a fresh TEST alert through independent approval, open Alerts, acknowledge
  it as a real signed-in recipient, and confirm the report contains the read receipt.
- Resolve/cancel it and verify removal on refresh. Expired/unpublished alerts stay
  hidden. No SMS job is created while SMS is disabled.
- Verify loading, empty/error and stale states; an outage must not display a cached
  result as current or imply that missing information means low risk.
- Check the exact release commit's CI and weather-worker outcomes separately.
  Current hosted prediction display remains a separate integration gate until
  implemented and tested; deploying the site does not complete that work.

If the API fails, inspect redacted service logs, health checks and environment
variable names. Roll back to the previous known-good deploy if necessary. The
database remains in Supabase across Render restarts; do not store user state on
the API filesystem. For web rollback/config changes, check the public URLs and
Supabase redirects again. Never paste private environment values into an issue.

## Issue tracking

This deployment contributes to #8, #13, #26, #29 and #30. It does not close their
broader acceptance criteria automatically. SMS/offline requirements in #10/#15
are deferred by the budget decision, not marked implemented. Use issue-linked
branches, conventional commit headers under 50 characters, and reviewed PRs.

References checked 25 November 2026:
[Blueprint specification](https://render.com/docs/blueprint-spec),
[static sites](https://render.com/docs/static-sites),
[rewrites](https://render.com/docs/redirects-rewrites),
[Python hosting and base pricing](https://render.com/hosting/python).
