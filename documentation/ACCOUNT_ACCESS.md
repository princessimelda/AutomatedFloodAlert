# Account access and recovery

The account screen previously replaced every failure with the same connection
and sign-in message. The UI now maps Supabase error codes to specific guidance
for incorrect credentials, unconfirmed email, rate limits, expired sessions and
connection failures. Raw provider messages, passwords and tokens are not shown
or logged by this handling.

Sign-in accepts an existing nonempty password; account creation and replacement
passwords retain the eight-character minimum. Email whitespace is removed, while
passwords are sent exactly as entered. A visibility toggle helps users check
their input.

## Recovery flow

1. Enter the account email and select **Forgot password**. A password is not
   required to request a reset. The response does not reveal whether an account
   exists.
2. Open the latest recovery email in the same browser used to request it. This
   preserves the PKCE verifier stored by the Supabase SDK.
3. The link returns to the existing allowlisted site origin. Supabase's
   `passwordRecovery` event causes the root account gate to show the new-password
   form rather than silently opening Home.
4. Enter matching replacement passwords. The SDK updates the authenticated
   user, and the app returns to Home after the `userUpdated` event.

Unconfirmed users can resend a signup confirmation email. Signed-in users can
also choose **Change password** on their account screen. Email actions use the
existing `confirmationRedirectUrl`; no new callback URL, database migration,
backend endpoint or privileged key is introduced.

## Deployment and verification

Only the Flutter static site needs rebuilding for this change. Its Supabase
project URL and publishable key must still match the account's project. Supabase
Authentication URL Configuration must allow the hosted site's origin, as for
the existing signup confirmation flow.

On 26 November 2026, read-only checks found the account service responding,
email sign-in enabled, signup enabled, email confirmation required, and the live
Flutter build containing the expected project URL and publishable key. Those
checks do not identify why a particular account was rejected; no user's password
or private account record was accessed.

Regression tests exercise credential and confirmation errors, recovery actions
without a password, callback redirect parameters, recovery-session navigation,
matching-password validation and the existing saved-place workflow. Real email
delivery and sign-in with the affected account still require a user check after
the frontend is deployed. Provider email limits and expired links remain visible
failures rather than successful account operations.

Validation: the full 82-test Flutter suite passed. After adding same-user
recovery and credential-submission regression cases, all 11 affected account/authentication tests passed
(84 distinct tests across those runs). Flutter analysis passed, and a release
web build completed successfully.

Repeated signup is not password recovery. Confirmation-required signup responses
do not prove that a new account was created, so the UI now directs existing users
to sign-in or password reset instead of implying that signup replaced their
existing password. A mock-provider regression test verifies that signup and
sign-in submit the same trimmed email and exact password, including whitespace
and non-ASCII characters.

References: [Supabase recovery flow](https://supabase.com/kb/troubleshooting/password-reset-link-logs-user-in-without-prompting-for-a-new-password-e51b22)
and [confirmation email resend](https://supabase.com/docs/reference/dart/auth-resend).
