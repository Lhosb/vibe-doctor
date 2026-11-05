# Discogs Recurring Collection Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep users' Discogs collections in sync automatically (nightly) and on demand (a "Sync now" button), without touching the existing `SyncDiscogsCollectionJob` or `DiscogsClient`.

**Architecture:** Two independent trigger paths both funnel into the existing, already-idempotent `SyncDiscogsCollectionJob`. A new `SyncAllDiscogsCollectionsJob` fans out one `SyncDiscogsCollectionJob` per connected user (scheduled nightly via Solid Queue's `config/recurring.yml`), and a new `resync` controller action enqueues a single `SyncDiscogsCollectionJob` for the current user from a button on the settings page.

**Tech Stack:** Rails 8.1, Solid Queue (recurring jobs + `perform_later`), RSpec (job specs, request specs), Capybara/system specs, WebMock for stubbing Discogs HTTP calls.

## Global Constraints

- No changes to `SyncDiscogsCollectionJob`, `DiscogsClient`, or `EnrichAlbumJob` — all reused as-is.
- Filter connected users on `discogs_token` presence only, not `discogs_username` (both are always saved together via `DiscogsConnectionsController#update`).
- Fan out to per-user jobs rather than looping/syncing inline in the recurring job, so one user's invalid token can't abort sync for everyone else.
- No notification/activity-feed surfacing of newly synced records, no handling for records removed from a Discogs collection, and no cooldown/rate-limiting on manual sync — all explicitly out of scope for this iteration.
- No dedicated spec for the `recurring.yml` entry itself (consistent with how `clear_solid_queue_finished_jobs` is handled today).

---

### Task 1: `SyncAllDiscogsCollectionsJob`

**Files:**
- Create: `app/jobs/sync_all_discogs_collections_job.rb`
- Test: `spec/jobs/sync_all_discogs_collections_job_spec.rb`

**Interfaces:**
- Consumes: `SyncDiscogsCollectionJob.perform_later(user)` (existing job, unchanged — takes a single `User`).
- Produces: `SyncAllDiscogsCollectionsJob` — a bare `perform` (no args), invocable via `perform_later`/`perform_now`, and referenced by class name from `config/recurring.yml` in Task 2.

- [ ] **Step 1: Write the failing spec**

```ruby
require "rails_helper"

RSpec.describe SyncAllDiscogsCollectionsJob, type: :job do
  let!(:connected_user) { create(:user, discogs_username: "listener", discogs_token: "test-token-abc") }
  let!(:disconnected_user) { create(:user, discogs_username: nil, discogs_token: nil) }

  it "enqueues SyncDiscogsCollectionJob only for users with a discogs_token" do
    expect {
      described_class.perform_now
    }.to have_enqueued_job(SyncDiscogsCollectionJob).with(connected_user).exactly(1).times

    expect(SyncDiscogsCollectionJob).not_to have_been_enqueued.with(disconnected_user)
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bin/rspec spec/jobs/sync_all_discogs_collections_job_spec.rb`
Expected: FAIL with `uninitialized constant SyncAllDiscogsCollectionsJob`

- [ ] **Step 3: Write the job**

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

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bin/rspec spec/jobs/sync_all_discogs_collections_job_spec.rb`
Expected: PASS (2 examples, 0 failures)

- [ ] **Step 5: Commit**

```bash
git add app/jobs/sync_all_discogs_collections_job.rb spec/jobs/sync_all_discogs_collections_job_spec.rb
git commit -m "Add SyncAllDiscogsCollectionsJob to fan out per-user Discogs syncs"
```

---

### Task 2: Nightly schedule via `config/recurring.yml`

**Files:**
- Modify: `config/recurring.yml`

**Interfaces:**
- Consumes: `SyncAllDiscogsCollectionsJob` (Task 1) referenced by class name.
- Produces: nothing consumed by later tasks — this is a leaf configuration change.

- [ ] **Step 1: Add the recurring entry**

Current `config/recurring.yml`:

```yaml
production:
  clear_solid_queue_finished_jobs:
    command: "SolidQueue::Job.clear_finished_in_batches(sleep_between_batches: 0.3)"
    schedule: every hour at minute 12
```

Change to:

```yaml
production:
  clear_solid_queue_finished_jobs:
    command: "SolidQueue::Job.clear_finished_in_batches(sleep_between_batches: 0.3)"
    schedule: every hour at minute 12
  sync_all_discogs_collections:
    class: SyncAllDiscogsCollectionsJob
    schedule: every day at 3am
```

- [ ] **Step 2: Verify the YAML parses and Solid Queue accepts the schedule**

Run: `bin/rails runner "puts Rails.application.config_for(:recurring)"`
Expected: prints a hash including `sync_all_discogs_collections: {class: 'SyncAllDiscogsCollectionsJob', schedule: 'every day at 3am'}` under `production` (or the currently loaded environment's equivalent — this file only defines a `production` key, so this command run in development will print an empty/nil result for the top-level key, which is expected; the important check is that the file parses without a YAML error)

- [ ] **Step 3: Commit**

```bash
git add config/recurring.yml
git commit -m "Schedule nightly Discogs collection sync for all connected users"
```

---

### Task 3: Manual "Sync now" button — route and controller action

**Files:**
- Modify: `config/routes.rb:6`
- Modify: `app/controllers/discogs_connections_controller.rb`
- Test: `spec/requests/discogs_connections_spec.rb`

**Interfaces:**
- Consumes: `SyncDiscogsCollectionJob.perform_later(user)` (existing job, unchanged).
- Produces: `resync_discogs_connection_path` (POST) route, usable by Task 4's view.

- [ ] **Step 1: Write the failing request spec**

Add to `spec/requests/discogs_connections_spec.rb` (inside the existing `RSpec.describe` block, after the `PATCH /discogs_connection` block):

```ruby
  describe "POST /discogs_connection/resync" do
    it "enqueues a sync job for the current user without requiring credentials" do
      expect {
        post resync_discogs_connection_path
      }.to have_enqueued_job(SyncDiscogsCollectionJob).with(user)

      expect(response).to redirect_to(library_path)
      expect(flash[:notice]).to eq("Discogs sync started.")
    end
  end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bin/rspec spec/requests/discogs_connections_spec.rb`
Expected: FAIL with `undefined local variable or method 'resync_discogs_connection_path'` (or a routing error)

- [ ] **Step 3: Add the route**

`config/routes.rb:6`, change:

```ruby
  resource :discogs_connection, only: %i[edit update]
```

to:

```ruby
  resource :discogs_connection, only: %i[edit update] do
    post :resync, on: :collection
  end
```

- [ ] **Step 4: Add the controller action**

`app/controllers/discogs_connections_controller.rb`, current file:

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

Change to:

```ruby
class DiscogsConnectionsController < ApplicationController
  def edit
  end

  def update
    Current.user.update!(discogs_connection_params)
    SyncDiscogsCollectionJob.perform_later(Current.user)
    redirect_to library_path, notice: "Discogs sync started."
  end

  def resync
    SyncDiscogsCollectionJob.perform_later(Current.user)
    redirect_to library_path, notice: "Discogs sync started."
  end

  private

  def discogs_connection_params
    params.permit(:discogs_username, :discogs_token)
  end
end
```

- [ ] **Step 5: Run the spec to verify it passes**

Run: `bin/rspec spec/requests/discogs_connections_spec.rb`
Expected: PASS (3 examples, 0 failures)

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/discogs_connections_controller.rb spec/requests/discogs_connections_spec.rb
git commit -m "Add resync action for manual Discogs collection sync"
```

---

### Task 4: "Sync now" button on the settings page

**Files:**
- Modify: `app/views/discogs_connections/edit.html.erb`
- Modify: `spec/system/discogs_connection_spec.rb`

**Interfaces:**
- Consumes: `resync_discogs_connection_path` (Task 3), `Current.user.discogs_token` (existing `User` attribute).
- Produces: nothing consumed by later tasks — this is the final task in the plan.

- [ ] **Step 1: Write the failing system spec**

Add a new test to `spec/system/discogs_connection_spec.rb` (after the existing `it` block, still inside the same `RSpec.describe` block so it shares the `let(:user)` and `before` stub):

```ruby
  it "shows a Sync now button once connected, and re-triggers the sync" do
    user.update!(discogs_username: "listener", discogs_token: "test-token-abc")

    visit new_session_path
    fill_in "Enter your email address", with: user.email_address
    fill_in "Enter your password", with: "s3cret-pass"
    click_button "Sign in"

    visit edit_discogs_connection_path

    expect(page).to have_button("Sync now")

    perform_enqueued_jobs do
      click_button "Sync now"
    end

    expect(page).to have_content("Discogs sync started.")
    expect(CollectionItem.where(user: user).count).to eq(1)
  end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bin/rspec spec/system/discogs_connection_spec.rb`
Expected: FAIL with `Unable to find button "Sync now"`

- [ ] **Step 3: Add the button to the view**

Current `app/views/discogs_connections/edit.html.erb`:

```erb
<div class="mx-auto md:w-2/3 w-full">
  <% if alert = flash[:alert] %>
    <p class="py-2 px-3 bg-red-50 mb-5 text-red-500 font-medium rounded-lg inline-block" id="alert"><%= alert %></p>
  <% end %>

  <h1 class="text-2xl font-bold">Discogs Settings</h1>

  <p class="my-4 text-sm text-gray-600">
    To get your token: go to Discogs &rarr;
    <%= link_to "Settings", "https://www.discogs.com/settings/developers", target: "_blank", rel: "noopener", class: "text-blue-600 underline" %>
    &rarr; Developers &rarr; Generate new token. Copy that value and paste it into the field below.
  </p>

  <%= form_with url: discogs_connection_path, method: :patch, class: "contents" do |form| %>
    <div class="my-5">
      <%= form.label :discogs_username %>
      <%= form.text_field :discogs_username, value: Current.user.discogs_username, required: true, class: "block border rounded-md px-3 py-2 mt-1 w-full" %>
    </div>

    <div class="my-5">
      <%= form.label :discogs_token, "Discogs personal access token" %>
      <%= form.text_field :discogs_token, value: Current.user.discogs_token, required: true, autocomplete: "off", class: "block border rounded-md px-3 py-2 mt-1 w-full" %>
    </div>

    <%= form.submit "Save", class: "rounded-md px-3.5 py-2.5 bg-blue-600 hover:bg-blue-500 text-white font-medium cursor-pointer" %>
  <% end %>
</div>
```

Change to:

```erb
<div class="mx-auto md:w-2/3 w-full">
  <% if alert = flash[:alert] %>
    <p class="py-2 px-3 bg-red-50 mb-5 text-red-500 font-medium rounded-lg inline-block" id="alert"><%= alert %></p>
  <% end %>

  <h1 class="text-2xl font-bold">Discogs Settings</h1>

  <p class="my-4 text-sm text-gray-600">
    To get your token: go to Discogs &rarr;
    <%= link_to "Settings", "https://www.discogs.com/settings/developers", target: "_blank", rel: "noopener", class: "text-blue-600 underline" %>
    &rarr; Developers &rarr; Generate new token. Copy that value and paste it into the field below.
  </p>

  <%= form_with url: discogs_connection_path, method: :patch, class: "contents" do |form| %>
    <div class="my-5">
      <%= form.label :discogs_username %>
      <%= form.text_field :discogs_username, value: Current.user.discogs_username, required: true, class: "block border rounded-md px-3 py-2 mt-1 w-full" %>
    </div>

    <div class="my-5">
      <%= form.label :discogs_token, "Discogs personal access token" %>
      <%= form.text_field :discogs_token, value: Current.user.discogs_token, required: true, autocomplete: "off", class: "block border rounded-md px-3 py-2 mt-1 w-full" %>
    </div>

    <%= form.submit "Save", class: "rounded-md px-3.5 py-2.5 bg-blue-600 hover:bg-blue-500 text-white font-medium cursor-pointer" %>
  <% end %>

  <% if Current.user.discogs_token.present? %>
    <%= button_to "Sync now", resync_discogs_connection_path, method: :post, class: "mt-3 rounded-md px-3.5 py-2.5 bg-gray-100 hover:bg-gray-200 text-gray-900 font-medium cursor-pointer" %>
  <% end %>
</div>
```

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bin/rspec spec/system/discogs_connection_spec.rb`
Expected: PASS (2 examples, 0 failures)

- [ ] **Step 5: Run the full spec suite to check for regressions**

Run: `bin/rspec`
Expected: all examples pass, 0 failures

- [ ] **Step 6: Commit**

```bash
git add app/views/discogs_connections/edit.html.erb spec/system/discogs_connection_spec.rb
git commit -m "Show Sync now button on Discogs settings page for connected users"
```

---

## Self-Review Notes

- **Spec coverage:** `SyncAllDiscogsCollectionsJob` (Task 1), nightly `recurring.yml` schedule (Task 2, intentionally untested per spec's Testing section), `resync` controller action (Task 3), and the visible button (Task 4) all map directly to the design doc's four sections plus its Testing section.
- **Placeholder scan:** no TBD/TODO markers; every step shows exact code and exact commands.
- **Type consistency:** `SyncAllDiscogsCollectionsJob#perform` takes no arguments (matches `class: SyncAllDiscogsCollectionsJob` in `recurring.yml`, which calls `perform_later` with no args). `resync_discogs_connection_path` (Task 3's route) matches the `button_to` call in Task 4. `SyncDiscogsCollectionJob.perform_later(user)` signature is used consistently across Tasks 1 and 3, matching its existing single-`User`-argument definition.
