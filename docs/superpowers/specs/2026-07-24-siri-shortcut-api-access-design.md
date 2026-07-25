# Siri Shortcut / Headless API Access — Design

## Problem

The original (Python) implementation of this app supported a headless flow:
speak a "vibe phrase" to Siri, an iOS Shortcut posts it to an endpoint, the
endpoint returns a recommendation, and Siri speaks the result back. That flow
doesn't exist in the Rails rewrite yet.

The `/recommend` POST endpoint (`RecommendationsController#create`) already
returns the right JSON shape (including an `explanation` string suitable for
Siri to speak), but it's only reachable through a signed cookie session plus
a CSRF token — both require an interactive browser login, which a headless
Shortcut can't do. There's also no per-user credential a Shortcut could send
instead.

## Approach

Add a per-user API token, checked as a fallback authentication path
alongside the existing cookie session, and a small self-service settings
page for viewing/regenerating it. Users are multiple (not single-tenant), so
the token must be scoped per-user, like the existing `discogs_token` field.

## Data model

- Migration: add `api_token` (string) to `users`, with a unique index.
- `User` gets `has_secure_token :api_token` (Rails built-in). This:
  - auto-generates a random token on user creation,
  - provides `regenerate_api_token!` for rotation,
  - stores the token in plaintext (not encrypted) so it can be looked up
    directly via `User.find_by(api_token:)` and redisplayed on the settings
    page. This mirrors how `discogs_token` is handled today (viewable,
    editable) rather than a hash-once-show-once pattern — consistent with
    "simplest approach" for this app's scale.

## Authentication

Extend `app/controllers/concerns/authentication.rb`:

- `require_authentication` tries, in order: cookie session
  (`resume_session`), then a bearer token (`resume_token_session`), then
  falls back to the existing `request_authentication` behavior.
- `resume_token_session` reads `request.authorization` for a `Bearer <token>`
  value, looks up `User.find_by(api_token:)`, and if found sets
  `Current.session = Session.new(user:)` — an **unpersisted** `Session`
  instance scoped to the current request only. No new `sessions` row, no
  cookie is set. `Current.user` (which delegates to `Current.session.user`)
  works unchanged for the rest of the request.
- `request_authentication` changes to return a JSON `401` (`{ "error":
  "unauthorized" }`) when the request format is JSON, instead of always
  redirecting to the login page. A Shortcut can't follow an HTML login
  redirect, so today's default behavior would silently break the flow.

This fallback lives in the shared `Authentication` concern (used by
`ApplicationController`), so any endpoint doubles as a token-authenticated
API automatically. In practice that means both `/recommend` (create) and
`/recommend/feedback` become Shortcut-reachable with no controller-specific
change beyond the CSRF exemption below.

## CSRF

Rails' `verify_authenticity_token` runs before our auth check and would
reject a token-authenticated POST (a Shortcut has no CSRF token). Scope the
skip narrowly, only to `RecommendationsController`, and only when a bearer
token is actually present on the request:

```ruby
skip_before_action :verify_authenticity_token, if: -> { request.authorization.present? }
```

Cookie-based browser requests (no `Authorization` header) keep full CSRF
protection unchanged.

## Settings page

New route:

```ruby
resource :api_access, only: [:edit] do
  post :regenerate, on: :collection
end
```

New `ApiAccessController` (thin, mirrors `DiscogsConnectionsController`):

```ruby
class ApiAccessController < ApplicationController
  def edit
  end

  def regenerate
    Current.user.regenerate_api_token!
    redirect_to edit_api_access_path, notice: "API token regenerated."
  end
end
```

`app/views/api_access/edit.html.erb`:

- Shows `Current.user.api_token` in a copyable, plain (unmasked) field —
  consistent with how the Discogs token is shown today.
- A "Regenerate" button (`button_to regenerate_api_access_path`) that
  immediately invalidates the old token (no grace period).
- Short instructions: a place to link a shareable iOS Shortcut (the user
  will create and share this separately) plus a one-line note on where to
  paste the token into it. Also states the minimal manual setup for anyone
  building their own Shortcut: `POST` the vibe phrase as `query` to
  `/recommend`, with header `Authorization: Bearer <token>`, and read the
  `explanation` field from the JSON response to speak.
- New sidebar link "API Access" in `app/views/shared/_sidebar.html.erb`,
  alongside the existing Discogs/Feedback links.

## Error handling

- Missing/invalid token or missing session, on a JSON request → `401`
  `{ "error": "unauthorized" }`.
- All existing `RecommendationsController` error handling (`NoCandidatesError`,
  `ActionController::ParameterMissing`, `InvalidOutcomeTransitionError`) is
  unchanged.

## Out of scope

- No token expiry, scopes, or multiple tokens per user — one token per user,
  rotated by full regeneration.
- No rate limiting on the token-authenticated path.
- Building/publishing the actual iOS Shortcut file — that's done by the user
  outside this codebase; the settings page just leaves room to link it.

## Testing

- `User` model spec: token auto-generated on create; `regenerate_api_token!`
  changes the value.
- `Authentication`/`RecommendationsController` request specs:
  - `POST /recommend` with a valid `Authorization: Bearer <token>` header,
    no cookie, no CSRF header → `200` with the expected JSON body.
  - `POST /recommend` with an invalid/unknown token → `401` JSON.
  - `POST /recommend` with no auth at all → `401` JSON (replacing today's
    redirect-to-login for this JSON path).
  - After `regenerate_api_token!`, the old token no longer authenticates.
- `ApiAccessController` request specs: `GET edit` renders the current token;
  `POST regenerate` changes `Current.user.api_token` and redirects with a
  notice.
