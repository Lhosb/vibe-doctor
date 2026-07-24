# Discogs Recurring Collection Sync — Design

## Problem

`SyncDiscogsCollectionJob` only runs once, triggered by
`DiscogsConnectionsController#update` when a user first saves (or edits)
their Discogs credentials. If a user adds a record to their Discogs
collection afterward, Vibe Doctor never finds out — there's no recurring
re-sync and Discogs has no webhook mechanism to push changes to us.

## Approach

Add two independent trigger paths that both funnel into the existing,
already-idempotent `SyncDiscogsCollectionJob` — no changes to that job or to
`DiscogsClient` are needed:

1. A new nightly recurring job, `SyncAllDiscogsCollectionsJob`, scheduled via
   Solid Queue's `config/recurring.yml`.
2. A manual "Sync now" button on the Discogs connection/settings page.

Fanning out to the existing per-user `SyncDiscogsCollectionJob` (rather than
looping and syncing inline in the recurring job) means one user's
expired/invalid token can't abort sync for everyone else — each per-user job
fails independently.

## `SyncAllDiscogsCollectionsJob`

New job, `app/jobs/sync_all_discogs_collections_job.rb`:

```ruby
class SyncAllDiscogsCollectionsJob < ApplicationJob
  queue_as :default

  def perform
    User.where.not(discogs_token: nil).find_each do |user|
      SyncDiscogsCollectionJob.perform_later(user)
    end
  end
end
```

Filters on `discogs_token` only, not `discogs_username`: both fields are
submitted and saved together in `DiscogsConnectionsController#update`
(`Current.user.update!(discogs_connection_params)`), so there's no path
where one is present without the other.

## Scheduling

`config/recurring.yml`, alongside the existing
`clear_solid_queue_finished_jobs` entry:

```yaml
production:
  clear_solid_queue_finished_jobs:
    command: "SolidQueue::Job.clear_finished_in_batches(sleep_between_batches: 0.3)"
    schedule: every hour at minute 12
  sync_all_discogs_collections:
    class: SyncAllDiscogsCollectionsJob
    schedule: every day at 3am
```

## Manual "Sync now" button

Add a `resync` action to `DiscogsConnectionsController`, routed as a member
action on the existing singular `discogs_connection` resource:

`config/routes.rb`:

```ruby
resource :discogs_connection, only: %i[edit update] do
  post :resync, on: :collection
end
```

`app/controllers/discogs_connections_controller.rb`:

```ruby
def resync
  SyncDiscogsCollectionJob.perform_later(Current.user)
  redirect_to library_path, notice: "Discogs sync started."
end
```

Button lives on `discogs_connections/edit.html.erb`, alongside the existing
credentials form, visible whenever `Current.user.discogs_token.present?`.

## Error handling

- **Invalid/revoked token**: `DiscogsClient` raises `DiscogsClient::Error` on
  non-success responses. `SyncDiscogsCollectionJob` doesn't rescue this
  today, so it propagates, Solid Queue's default retry/backoff applies, and
  it eventually lands in the failed jobs table. This is the same failure
  mode that exists today for the one-time sync — now it just repeats
  nightly instead of once. A user with a permanently broken token will fail
  silently every night; there's no notification for this yet (see Out of
  scope). Known gap, not solved here.
- **Partial failure across users**: isolated by design — each user gets
  their own `SyncDiscogsCollectionJob`, so one broken token doesn't block
  anyone else's sync.
- **Manual sync spam**: no cooldown/rate-limit on the "Sync now" button.
  The underlying job is idempotent and repeated syncs are cheap; not worth
  the complexity for v1.

## Out of scope

- No notification/activity-feed surfacing of newly synced records — they
  simply appear in the library next time the user visits it. No
  Notification model, email, or Turbo Stream broadcast is being added.
- No handling for records *removed* from a user's Discogs collection — this
  design only addresses additions.
- No cooldown/rate-limiting on manual sync.
- No changes to `SyncDiscogsCollectionJob`, `DiscogsClient`, or the
  enrichment/grounding pipeline (`EnrichAlbumJob`) — all reused as-is.

## Testing

- `SyncAllDiscogsCollectionsJob` spec: given users with and without
  `discogs_token`, asserts `SyncDiscogsCollectionJob` is enqueued only for
  connected users (`assert_enqueued_with`).
- `DiscogsConnectionsController#resync` request spec: mirrors the existing
  `update` request spec — asserts `SyncDiscogsCollectionJob.perform_later` is
  enqueued for `Current.user` and a flash notice is set, without requiring
  credentials to be resubmitted.
- No dedicated spec for the `recurring.yml` entry itself, consistent with
  how `clear_solid_queue_finished_jobs` is handled today.
- Existing `SyncDiscogsCollectionJob` and system specs are untouched and
  already cover the "new record → new Album → EnrichAlbumJob" path this
  design reuses.
