# Guided assistant

Help offers predefined questions, with answers retrieved from Supabase through
the backend. It uses no language model, paid AI API, free-text input or saved
conversation history.

The initial five English questions explain live-data limitations, choosing a
place, unavailable risk data, preparedness steps and route limitations. These
are app-help answers checked against the implementation, not reviewed emergency
instructions. Safety guidance and Kiswahili content require separate review.

## Data and API

Migration `202610280002_guided_assistant.sql` adds `assistant_answers`, the tenth
application table. Answers include language, category, source, HTTPS source URL,
content-check date, expiry date and publication status. The restricted backend
reader sees only published, currently valid answers; direct client access is denied.

- `GET /v1/assistant/questions?language=en`: available question catalogue.
- `GET /v1/assistant/questions/{id}?language=en`: selected answer and provenance.

The UI handles loading, retries, withdrawn/expired answers and empty catalogues.
It never generates a fallback answer. Buttons support enlarged text and scrolling,
have a minimum 48-pixel height, and answer updates use accessibility live regions.
Expiry timers are bounded to one day and recheck validity before removing an
answer. Scheduling a full 90-day expiry exceeds the browser timer range and can
hide a valid answer immediately; the long-lived-answer regression test covers
bounded rechecks and removal when the actual expiry is reached.

## Publishing more content

Prepare a question and answer with a verifiable source. Review wording, scope,
language and expiry before setting `is_published=true` through a trusted database
administration connection. There is no public publishing endpoint. Re-review the
initial answers within 90 days; expired content disappears.

This is an initial guided-assistant slice of chat issues #16–#20, not completion
of the entire milestone. Prioritise reviewed local guidance and user testing
before adding conversational AI or personalised risk claims.
