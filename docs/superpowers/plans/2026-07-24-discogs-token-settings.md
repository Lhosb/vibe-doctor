# Discogs Token Settings Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the existing Discogs "connect" (`new`/`create`, first-connect-only) flow into an `edit`/`update` settings page so users can both add and later update their Discogs username/token from one page, with on-page instructions for generating the token.

**Architecture:** Rename `DiscogsConnectionsController#new`/`#create` to `#edit`/`#update` (matching the `edit`/`update` pattern already used by `RegistrationsController` in this app). The route becomes `resource :discogs_connection, only: %i[edit update]`. The view pre-fills the form with the current user's saved username/token, adds an instructions block, and renders a flash alert. Two existing callers (`library/index.html.erb`, `shared/_sidebar.html.erb`) are updated to point at the new path; the sidebar gains a new "Discogs" nav item.

**Tech Stack:** Rails 8.1, RSpec (request + system specs), Capybara, `ActiveJob::TestHelper`, WebMock (`stub_request`), FactoryBot.

## Global Constraints

- Token field stays a plain `text_field` (not masked/`password_field`) — this was an explicit design decision.
- Every successful save (first connect or later update) must re-enqueue `SyncDiscogsCollectionJob.perform_later(Current.user)`.
- No new migration — `discogs_token`/`discogs_username` columns and `encrypts :discogs_token` already exist on `User` (`app/models/user.rb:10`).
- No changes to `DiscogsClient` or `SyncDiscogsCollectionJob` — both already read from `Current.user` correctly.
- Follow existing view conventions exactly: Tailwind classes and flash markup as seen in `app/views/registrations/edit.html.erb`.

---

### Task 1: Route and controller — `edit`/`update`

**Files:**
- Modify: `config/routes.rb:6` (currently `resource :discogs_connection, only: %i[new create]`)
- Modify: `app/controllers/discogs_connections_controller.rb`
- Test: `spec/requests/discogs_connections_spec.rb` (new file)

**Interfaces:**
- Produces: `edit_discogs_connection_path` (GET), `discogs_connection_path` (PATCH) — used by Task 2's view and Task 3's callers.
- Consumes: `Current.user` (set by `ApplicationController`'s `Authentication` concern), `SyncDiscogsCollectionJob.perform_later(user)` (existing job, unchanged signature).

- [ ] **Step 1: Write the failing request spec**

Create `spec/requests/discogs_connections_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Discogs connection settings", type: :request do
  let(:user) { create(:user, discogs_username: "listener", discogs_token: "old-token") }

  before { sign_in_as(user) }

  describe "GET /discogs_connection/edit" do
    it "renders the form pre-filled with the current username and token" do
      get edit_discogs_connection_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('value="listener"')
      expect(response.body).to include('value="old-token"')
    end
  end

  describe "PATCH /discogs_connection" do
    it "saves the new username/token and re-enqueues the sync job" do
      expect {
        patch discogs_connection_path, params: { discogs_username: "newname", discogs_token: "new-token" }
      }.to have_enqueued_job(SyncDiscogsCollectionJob).with(user)

      expect(response).to redirect_to(library_path)
      user.reload
      expect(user.discogs_username).to eq("newname")
      expect(user.discogs_token).to eq("new-token")
    end
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/requests/discogs_connections_spec.rb`
Expected: FAIL — `edit_discogs_connection_path`/`discogs_connection_path` (PATCH) undefined, because the route is still `only: %i[new create]`.

- [ ] **Step 3: Update the route**

In `config/routes.rb`, change:

```ruby
resource :discogs_connection, only: %i[new create]
```

to:

```ruby
resource :discogs_connection, only: %i[edit update]
```

- [ ] **Step 4: Update the controller**

Replace the contents of `app/controllers/discogs_connections_controller.rb`:

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

- [ ] **Step 5: Run the spec again to verify it still fails on the view**

Run: `bundle exec rspec spec/requests/discogs_connections_spec.rb`
Expected: FAIL — `ActionView::MissingTemplate` for `discogs_connections/edit` (the view is still named `new.html.erb` and doesn't have the pre-filled fields). This is expected; Task 2 fixes it.

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/discogs_connections_controller.rb spec/requests/discogs_connections_spec.rb
git commit -m "Convert Discogs connection route/controller to edit/update"
```

---

### Task 2: View — pre-filled form with instructions

**Files:**
- Create: `app/views/discogs_connections/edit.html.erb`
- Delete: `app/views/discogs_connections/new.html.erb`
- Test: `spec/requests/discogs_connections_spec.rb` (from Task 1 — should now pass)

**Interfaces:**
- Consumes: `edit_discogs_connection_path` / `discogs_connection_path` from Task 1; `Current.user.discogs_username`, `Current.user.discogs_token`.
- Produces: form submit button labeled `"Save"` (Task 3's system spec update depends on this exact label).

- [ ] **Step 1: Delete the old view and create the new one**

```bash
git rm app/views/discogs_connections/new.html.erb
```

Create `app/views/discogs_connections/edit.html.erb`:

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
      <%= form.text_field :discogs_username, value: Current.user.discogs_username, class: "block border rounded-md px-3 py-2 mt-1 w-full" %>
    </div>

    <div class="my-5">
      <%= form.label :discogs_token, "Discogs personal access token" %>
      <%= form.text_field :discogs_token, value: Current.user.discogs_token, class: "block border rounded-md px-3 py-2 mt-1 w-full" %>
    </div>

    <%= form.submit "Save", class: "rounded-md px-3.5 py-2.5 bg-blue-600 hover:bg-blue-500 text-white font-medium cursor-pointer" %>
  <% end %>
</div>
```

- [ ] **Step 2: Run the Task 1 request spec to verify it now passes**

Run: `bundle exec rspec spec/requests/discogs_connections_spec.rb`
Expected: PASS (2 examples)

- [ ] **Step 3: Commit**

```bash
git add app/views/discogs_connections/edit.html.erb app/views/discogs_connections/new.html.erb
git commit -m "Add pre-filled Discogs settings view with token instructions"
```

---

### Task 3: Update callers — library link, sidebar nav, and the existing system spec

**Files:**
- Modify: `app/views/library/index.html.erb:4`
- Modify: `app/views/shared/_sidebar.html.erb`
- Modify: `spec/system/discogs_connection_spec.rb`
- Test: `spec/requests/library_spec.rb` (existing — must still pass unmodified)

**Interfaces:**
- Consumes: `edit_discogs_connection_path` (Task 1).

- [ ] **Step 1: Update the library "Connect Discogs" link**

In `app/views/library/index.html.erb`, change line 4 from:

```erb
  <%= link_to "Connect Discogs", new_discogs_connection_path, class: "text-blue-600 underline" %>
```

to:

```erb
  <%= link_to "Connect Discogs", edit_discogs_connection_path, class: "text-blue-600 underline" %>
```

(Link text is unchanged — this keeps `spec/requests/library_spec.rb`'s `"shows the Connect Discogs prompt..."` example passing without modification.)

- [ ] **Step 2: Add a "Discogs" nav link to the sidebar**

In `app/views/shared/_sidebar.html.erb`, add a new `<li>` immediately after the Feedback `<li>` (after line 45's `</li>`, before the `<% if Current.user&.admin? %>` block on line 46):

```erb
        <li>
          <%= link_to edit_discogs_connection_path, class: "flex items-center p-2 text-gray-900 rounded-lg dark:text-white hover:bg-gray-100 dark:hover:bg-gray-700 group" do %>
            <svg class="w-6 h-6 text-gray-500 transition duration-75 dark:text-gray-400 group-hover:text-gray-900 dark:group-hover:text-white" aria-hidden="true" fill="currentColor" viewBox="0 0 20 20" xmlns="http://www.w3.org/2000/svg"><path fill-rule="evenodd" d="M11.49 3.17c-.38-1.56-2.6-1.56-2.98 0a1.532 1.532 0 01-2.286.948c-1.372-.836-2.942.734-2.106 2.106.54.886.061 2.042-.947 2.287-1.561.379-1.561 2.6 0 2.978a1.532 1.532 0 01.947 2.287c-.836 1.372.734 2.942 2.106 2.106a1.532 1.532 0 012.287.947c.379 1.561 2.6 1.561 2.978 0a1.533 1.533 0 012.287-.947c1.372.836 2.942-.734 2.106-2.106a1.533 1.533 0 01.947-2.287c1.561-.379 1.561-2.6 0-2.978a1.532 1.532 0 01-.947-2.287c.836-1.372-.734-2.942-2.106-2.106a1.532 1.532 0 01-2.287-.947zM10 13a3 3 0 100-6 3 3 0 000 6z" clip-rule="evenodd"></path></svg>
            <span class="ms-3">Discogs</span>
          <% end %>
        </li>
```

- [ ] **Step 3: Update the existing system spec for the renamed button**

In `spec/system/discogs_connection_spec.rb`, change line 46 from:

```ruby
      click_button "Connect"
```

to:

```ruby
      click_button "Save"
```

- [ ] **Step 4: Run both specs to verify they pass**

Run: `bundle exec rspec spec/system/discogs_connection_spec.rb spec/requests/library_spec.rb`
Expected: PASS (all examples, including `"shows nav links positioned Library < Vibe Map < Recommend < Feedback"` — unaffected since Discogs is appended after Feedback)

- [ ] **Step 5: Commit**

```bash
git add app/views/library/index.html.erb app/views/shared/_sidebar.html.erb spec/system/discogs_connection_spec.rb
git commit -m "Point Discogs connection link/nav at the new settings page"
```

---

### Task 4: Full suite verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `bundle exec rspec`
Expected: PASS, 0 failures.

- [ ] **Step 2: Manually sanity-check the route table**

Run: `bin/rails routes | grep discogs_connection`
Expected: two lines only —

```
edit_discogs_connection GET    /discogs_connection/edit  discogs_connections#edit
     discogs_connection PATCH  /discogs_connection       discogs_connections#update
```

(no `new`/`create`/`POST` entries remaining)
