# Accounts and saved places

Sign-in is optional. Home, place selection, preparedness and the guide remain
available to guests. The profile button opens email/password sign-in, account
creation, saved-place management and sign-out. Email confirmation is honoured.

The official Supabase Flutter SDK persists and refreshes the session. Passwords
are not saved by application code. A restored session loads its default saved
place unless the user has already selected a place. Sign-out/account changes
clear the current dashboard and saved-place state and invalidate pending default
and location requests. Saving places does not subscribe users to alerts.

## Configuration

Copy `config.example.json` to ignored `config.local.json`. Set the project URL
and **publishable** key from Supabase Connect / API Keys. Never include a database
password or service-role/secret key in Flutter. The publishable key is public;
PostgreSQL owner RLS protects user records. Run from the Flutter directory:

```
flutter run -d chrome --dart-define-from-file=config.local.json
flutter build web --no-web-resources-cdn --dart-define-from-file=config.local.json
```

Keep the local API URL for development; deployment needs the hosted HTTPS API.
Supabase's Data API must expose the public schema and Email authentication must
be enabled. Configure the Auth Site URL / allowed redirect URLs for the preview
and eventual deployed site so confirmation returns to the app. Native deep-link
configuration needs verification before distributing an Android/iOS build.

For the current local preview, set Site URL and add an allowed Redirect URL of
`http://127.0.0.1:8765` in Authentication → URL Configuration. Web signup explicitly
requests the current browser origin as its email redirect. Use the same browser
and origin when opening the confirmation email so the SDK can complete PKCE.
Old emailed links retain their original destination; use a fresh confirmation
link to test the changed settings. An already confirmed account can sign in
directly without another signup.

## Database

Migration `202610280003_saved_place_defaults.sql` extends existing owner-private
`saved_places` with a catalogue `place_id` and `is_default`, avoiding storage of
precise GPS coordinates for this flow. A unique index prevents duplicate saves;
a second allows at most one default per user. `set_default_place` uses invoker
security, owner RLS, and a per-user transaction lock for atomic default switching.
Authenticated users can read only published place metadata. No new FastAPI
personal-data endpoints or trusted keys in the app are required.

Saved places with unpublished/deleted catalogue entries are omitted from the UI.
Removing the default leaves no default until another is chosen. The old phone/OTP
demonstration is no longer reachable from app navigation. Sample Flood News is
hidden pending sourced Weather updates.

## Validation and remaining setup

Widget tests cover account actions, restored defaults and sign-out. Isolated
PostgreSQL tests cover owner isolation, forbidden writes, default switching and
migration rollback. The hosted migration is applied. Public configuration was
verified on 2026-10-28: Auth settings returned HTTP 200 with Email enabled and
anonymous saved-place access returned HTTP 401. Hosted signup, email delivery,
browser session restoration and authenticated Data API access still need an
end-to-end check with a development account; tests create no real accounts.
Password recovery, account deletion and native confirmation deep links remain
follow-up work before a public account release.
