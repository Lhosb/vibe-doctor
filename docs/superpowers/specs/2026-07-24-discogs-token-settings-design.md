# Discogs Token Settings Page — Design

## Problem

Users need a page to add or update their Discogs personal access token (and
username), with on-page instructions for generating that token on Discogs.
The current flow (`DiscogsConnectionsController#new`/`#create`) only supports
first-time connection — there's no way to revisit and change an
already-saved token.

## Approach

Extend the existing `discogs_connection` singular resource into an
`edit`/`update` flow, matching the `edit`/`update` pattern this app already
uses for `Registrations`. One page serves both first-time connect and later
updates — no separate "connect" vs "settings" page.

## Routes

`config/routes.rb`:

```ruby
resource :discogs_connection, only: %i[edit update]
```

Replaces the current `only: %i[new create]`.

## Controller

`app/controllers/discogs_connections_controller.rb`:

```ruby
class DiscogsConnectionsController < ApplicationController
  def edit
  end

  def update
    Current.user.update!(discogs_connection_params)
    SyncDiscogsCollectionJob.perform_later(Current.user)
    redirect_to library_path, notice: "Discogs sync started."
  end

  private

  def discogs_connection_params
    params.permit(:discogs_username, :discogs_token)
  end
end
```

Every successful save (first connect or later update) re-enqueues
`SyncDiscogsCollectionJob`, consistent with today's `create` behavior.

## View

`app/views/discogs_connections/edit.html.erb` (renamed from `new.html.erb`):

- Form posts via `PATCH` to `discogs_connection_path`.
- `discogs_username` and `discogs_token` fields are plain `text_field`s (not
  masked), pre-filled with `Current.user.discogs_username` /
  `Current.user.discogs_token`. Since the real current value is shown,
  submitting the form always saves whatever is in the fields — no "leave
  blank to keep unchanged" behavior is needed.
- Flash notice/alert block matching the pattern in `sessions/new.html.erb`
  (this view currently has no flash rendering).
- An instructions block above the form:

  > To get your token: go to Discogs → Settings → Developers → Generate new
  > token. Copy that value and paste it into the field below.

  with a link to `https://www.discogs.com/settings/developers`.
- Heading changes from "Connect Discogs" to "Discogs Settings".

## Callers to update

- `app/views/library/index.html.erb:4` — `new_discogs_connection_path` →
  `edit_discogs_connection_path`.
- `app/views/shared/_sidebar.html.erb` — add a new nav `<li>` (matching the
  existing Library/Vibe Map/Recommend/Feedback items) linking to
  `edit_discogs_connection_path`, labeled "Discogs".

## Out of scope

- No new migration — `discogs_token` and `discogs_username` columns and the
  `encrypts :discogs_token` declaration already exist on `User`.
- No masking/obfuscation of the token field.
- No changes to `DiscogsClient` or `SyncDiscogsCollectionJob` — both already
  take the token/username from `Current.user` correctly.
- No general "Account Settings" page — this stays scoped to the Discogs
  connection.

## Testing

- Request spec for `DiscogsConnectionsController`, replacing any existing
  `#create` coverage:
  - `GET edit` renders the form pre-filled with the current user's
    `discogs_username`/`discogs_token`.
  - `PATCH update` with valid params saves the attributes and enqueues
    `SyncDiscogsCollectionJob`.
