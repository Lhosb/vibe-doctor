# Recommend Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `GET /recommend` page where a signed-in user types a vibe phrase (optionally a genre), gets back one recommended album via the existing `POST /recommend` endpoint, and can jump straight to giving feedback on that specific recommendation.

**Architecture:** A thin `RecommendController#index` renders a static Tailwind form. A new `recommend` Stimulus controller intercepts the form submit, POSTs to the existing unchanged `/recommend` JSON endpoint, and renders the result (or an inline error) client-side. `FeedbackController#index` gets an additive `recommendation_event_id` param so the result panel's "Give feedback" link can jump straight to that event's card instead of whatever is oldest-pending.

**Tech Stack:** Rails 8.1, Hotwire (Turbo + Stimulus), Import Maps, Tailwind, RSpec + Capybara (`selenium`/headless Chrome for `js: true` system specs).

## Global Constraints

- No changes to `RecommendationPipeline`, `RecommendationsController`, or the `POST /recommend` request/response contract.
- No genre *picker* — the genre field is a plain optional text input passed straight through as the `genre` param.
- No result history — the page always shows exactly the single best match the pipeline returns.
- No change to how `RecommendationEvent` outcomes are recorded or scored (`AlbumAffinity`, `ArtistCooldown`).
- No Turbo Stream response format added to `POST /recommend` — reuse the existing JSON contract as-is.
- Domain/business logic stays on models per this repo's `CLAUDE.md`; this feature has no new domain logic, only a thin controller, a view, and a Stimulus controller — no `app/services` object needed.

---

## Task 1: `GET /recommend` route, controller, and view scaffold

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/recommend_controller.rb`
- Create: `app/views/recommend/index.html.erb`
- Test: `spec/requests/recommend_spec.rb`

**Interfaces:**
- Produces: route helper `recommend_path` (`GET /recommend`, named `:recommend`). View renders a `data-controller="recommend"` wrapper containing a form with inputs carrying `data-recommend-target="query"` and `data-recommend-target="genre"`, a submit control carrying `data-recommend-target="submit"`, a form-level `data-action="submit->recommend#submit"`, and an empty result container carrying `data-recommend-target="result"`. These exact target names are consumed by Task 3's Stimulus controller.

- [ ] **Step 1: Write the failing request spec**

Create `spec/requests/recommend_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "GET /recommend", type: :request do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  it "renders the recommend form" do
    get "/recommend"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(data-recommend-target="query"))
    expect(response.body).to include(%(data-recommend-target="genre"))
    expect(response.body).to include(%(data-recommend-target="result"))
  end

  it "requires authentication" do
    delete session_path

    get "/recommend"

    expect(response).to have_http_status(:redirect)
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/requests/recommend_spec.rb`
Expected: FAIL — `ActionController::RoutingError` / `uninitialized constant RecommendController` (route and controller don't exist yet).

- [ ] **Step 3: Add the route**

In `config/routes.rb`, add the new `GET` route immediately before the existing `post "/recommend", to: "recommendations#create"` line (the `POST /recommend` route has no `as:` today, so `:recommend` is free to name):

```ruby
  get "/feedback", to: "feedback#index"
  post "/feedback", to: "feedback#create"
  get "/recommend", to: "recommend#index", as: :recommend
  post "/recommend", to: "recommendations#create"
  post "/recommend/feedback", to: "recommendations#feedback"
```

- [ ] **Step 4: Add the controller**

Create `app/controllers/recommend_controller.rb`:

```ruby
class RecommendController < ApplicationController
  def index
  end
end
```

- [ ] **Step 5: Add the view**

Create `app/views/recommend/index.html.erb`:

```erb
<h1 class="text-2xl font-bold mb-4">Recommend</h1>

<div class="max-w-xl" data-controller="recommend">
  <%= form_with url: "/recommend", method: :post, data: { turbo: "false", action: "submit->recommend#submit" }, class: "contents" do |form| %>
    <div class="mb-4">
      <%= form.label :query, "What are you in the mood for?", class: "block text-sm font-medium text-gray-700 mb-1" %>
      <%= form.text_field :query, required: true, placeholder: "e.g. warm sunday jazz", data: { recommend_target: "query" }, class: "block shadow-sm rounded-md border border-gray-400 focus:outline-blue-600 px-3 py-2 w-full" %>
    </div>

    <div class="mb-4">
      <%= form.label :genre, "Genre (optional)", class: "block text-sm font-medium text-gray-700 mb-1" %>
      <%= form.text_field :genre, placeholder: "e.g. Jazz", data: { recommend_target: "genre" }, class: "block shadow-sm rounded-md border border-gray-400 focus:outline-blue-600 px-3 py-2 w-full" %>
    </div>

    <%= form.submit "Get a recommendation", data: { recommend_target: "submit" }, class: "rounded-md px-3.5 py-2.5 bg-blue-600 hover:bg-blue-500 text-white font-medium cursor-pointer disabled:opacity-50" %>
  <% end %>

  <div class="mt-6" data-recommend-target="result"></div>
</div>
```

Note: `data-turbo="false"` stops Turbo Drive from intercepting this form's submit (it would otherwise race the Stimulus controller's own `fetch`). The Stimulus controller (Task 3) calls `event.preventDefault()` in its bubble-phase `submit` handler, which still cancels the native browser submission since Turbo is no longer competing for the event.

- [ ] **Step 6: Run the spec to verify it passes**

Run: `bundle exec rspec spec/requests/recommend_spec.rb`
Expected: PASS (2 examples).

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/controllers/recommend_controller.rb app/views/recommend/index.html.erb spec/requests/recommend_spec.rb
git commit -m "Add GET /recommend route, controller, and form view"
```

---

## Task 2: `FeedbackController` — resolve a requested pending event

**Files:**
- Modify: `app/controllers/feedback_controller.rb`
- Test: `spec/requests/feedback_spec.rb`

**Interfaces:**
- Consumes: `RecommendationEvent.pending_for(user)` (existing scope, `app/models/recommendation_event.rb:14`), `current_user.recommendation_events` (existing `has_many`, `app/models/user.rb:6`), enum-generated `.pending` scope on `RecommendationEvent`.
- Produces: `GET /feedback?recommendation_event_id=<id>` now shows that event's card when it belongs to the current user and is still pending; every other case (param absent, wrong user's event, already-actioned event, bad id) falls back to today's oldest-pending behavior. Consumed by Task 3's system spec, which clicks a "Give feedback" link built as `/feedback?recommendation_event_id=<id>`.

- [ ] **Step 1: Write the failing request specs**

In `spec/requests/feedback_spec.rb`, add these examples inside the existing `RSpec.describe "GET /feedback", type: :request do ... end` block (after the two existing `it` blocks, before the closing `end`):

```ruby
  it "shows the requested event when it belongs to the current user and is still pending" do
    create(:recommendation_event, user: user, album: create(:album, title: "Older Album"), outcome: "pending")
    target_event = create(:recommendation_event, user: user, album: create(:album, title: "Target Album"), outcome: "pending")

    get "/feedback", params: { recommendation_event_id: target_event.id }

    expect(response.body).to include("Target Album")
    expect(response.body).not_to include("Older Album")
  end

  it "falls back to the oldest pending event for another user's event id" do
    create(:recommendation_event, user: user, album: create(:album, title: "Own Album"), outcome: "pending")
    other_user = create(:user)
    other_event = create(:recommendation_event, user: other_user, album: create(:album, title: "Other Album"), outcome: "pending")

    get "/feedback", params: { recommendation_event_id: other_event.id }

    expect(response.body).to include("Own Album")
    expect(response.body).not_to include("Other Album")
  end

  it "falls back to the oldest pending event for an already-actioned event id" do
    create(:recommendation_event, user: user, album: create(:album, title: "Own Album"), outcome: "pending")
    actioned_event = create(:recommendation_event, user: user, album: create(:album, title: "Actioned Album"), outcome: "good")

    get "/feedback", params: { recommendation_event_id: actioned_event.id }

    expect(response.body).to include("Own Album")
    expect(response.body).not_to include("Actioned Album")
  end
```

- [ ] **Step 2: Run the specs to verify the new ones fail**

Run: `bundle exec rspec spec/requests/feedback_spec.rb`
Expected: the 2 pre-existing examples PASS; the 3 new examples FAIL (currently `GET /feedback` ignores `params[:recommendation_event_id]` entirely, so the "Older Album" / "Other Album" / "Actioned Album" cards show up instead of being excluded).

- [ ] **Step 3: Implement the fallback resolution**

Replace the body of `app/controllers/feedback_controller.rb`'s `index` action:

```ruby
class FeedbackController < ApplicationController
  def index
    @event = pending_event_for(params[:recommendation_event_id])
  end

  def create
    event = current_user.recommendation_events.find(params.require(:recommendation_event_id))
    event.apply_outcome!(params.require(:outcome))

    @event = RecommendationEvent.pending_for(current_user).first
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to feedback_path }
    end
  rescue ActiveRecord::RecordNotFound
    head :not_found
  rescue RecommendationEvent::InvalidOutcomeTransitionError, ActionController::ParameterMissing
    head :unprocessable_content
  end

  private

  def pending_event_for(id)
    return RecommendationEvent.pending_for(current_user).first if id.blank?

    current_user.recommendation_events.pending.find_by(id: id) ||
      RecommendationEvent.pending_for(current_user).first
  end
end
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `bundle exec rspec spec/requests/feedback_spec.rb`
Expected: PASS (5 examples: 2 pre-existing + 3 new).

- [ ] **Step 5: Commit**

```bash
git add app/controllers/feedback_controller.rb spec/requests/feedback_spec.rb
git commit -m "Let GET /feedback show a specific pending event by id"
```

---

## Task 3: Recommend page — Stimulus controller happy path

**Files:**
- Create: `app/javascript/controllers/recommend_controller.js`
- Test: `spec/system/recommend_spec.rb`

**Interfaces:**
- Consumes: Task 1's view targets (`data-recommend-target="query"|"genre"|"submit"|"result"`), the existing `POST /recommend` JSON contract (`{ recommendation_event_id, album: { id, title, artists, genres }, explanation }` on `200`), Task 2's `GET /feedback?recommendation_event_id=<id>` behavior.
- Produces: Stimulus controller identifier `recommend` with action `submit(event)`. Renders a result block containing the album title, artists, explanation, a link to `/albums/<id>`, and a link to `/feedback?recommendation_event_id=<id>`.

- [ ] **Step 1: Write the failing system spec**

Create `spec/system/recommend_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Recommend page", type: :system, js: true do
  let(:user) { create(:user) }
  let(:album) { create(:album, :grounded, title: "Kind of Blue", artists: [ "Miles Davis" ], genres: [ "Jazz" ]) }

  before { sign_in_as(user) }

  it "recommends an album and links to giving feedback on it" do
    event = create(:recommendation_event, user: user, album: album, explanation: "warm and mellow", outcome: "pending")
    result = RecommendationPipeline::Result.new(album: album, explanation: "warm and mellow", recommendation_event: event)
    pipeline = instance_double(RecommendationPipeline, call: result)
    allow(RecommendationPipeline).to receive(:new)
      .with(user: user, query_text: "warm sunday jazz", genre: nil)
      .and_return(pipeline)

    visit "/recommend"
    fill_in "What are you in the mood for?", with: "warm sunday jazz"
    click_button "Get a recommendation"

    expect(page).to have_content("Kind of Blue")
    expect(page).to have_content("Miles Davis")
    expect(page).to have_content("warm and mellow")

    click_link "Give feedback"

    expect(page).to have_current_path(%r{\A/feedback})
    expect(page).to have_content("Kind of Blue")
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/system/recommend_spec.rb`
Expected: FAIL — clicking "Get a recommendation" does nothing observable (no `recommend` Stimulus controller registered yet, so `data-action="submit->recommend#submit"` has no handler and the browser attempts a native form submission that Capybara's headless Chrome driver won't navigate meaningfully for this test's expectations).

- [ ] **Step 3: Implement the Stimulus controller (happy path)**

Create `app/javascript/controllers/recommend_controller.js`:

```js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["query", "genre", "submit", "result"];

  submit(event) {
    event.preventDefault();
    if (this.requestInFlight) return;

    const query = this.queryTarget.value;
    const genre = this.genreTarget.value.trim();

    const formData = new FormData();
    formData.append("query", query);
    if (genre !== "") formData.append("genre", genre);

    const headers = {};
    const csrfToken = document.querySelector(
      'meta[name="csrf-token"]',
    )?.content;
    if (csrfToken) headers["X-CSRF-Token"] = csrfToken;

    this.requestInFlight = true;
    this.submitTarget.disabled = true;

    fetch("/recommend", { method: "POST", headers, body: formData })
      .then((response) => response.json().then((body) => ({ ok: response.ok, body })))
      .then(({ ok, body }) => {
        if (ok) this.renderResult(body);
      })
      .finally(() => {
        this.requestInFlight = false;
        this.submitTarget.disabled = false;
      });
  }

  renderResult({ album, explanation, recommendation_event_id }) {
    this.resultTarget.textContent = "";

    const wrapper = document.createElement("div");
    wrapper.className = "p-4 border border-gray-200 rounded-lg bg-gray-50";

    const title = document.createElement("h2");
    title.className = "text-lg font-semibold";
    title.textContent = album.title;

    const artists = document.createElement("p");
    artists.className = "text-gray-600";
    artists.textContent = album.artists.join(", ");

    const explanationEl = document.createElement("p");
    explanationEl.className = "mt-2 text-gray-800";
    explanationEl.textContent = explanation;

    const links = document.createElement("div");
    links.className = "mt-4 flex gap-4";

    const albumLink = document.createElement("a");
    albumLink.href = `/albums/${album.id}`;
    albumLink.className = "text-blue-600 underline hover:no-underline";
    albumLink.textContent = "View album";

    const feedbackLink = document.createElement("a");
    feedbackLink.href = `/feedback?recommendation_event_id=${recommendation_event_id}`;
    feedbackLink.className = "text-blue-600 underline hover:no-underline";
    feedbackLink.textContent = "Give feedback";

    links.append(albumLink, feedbackLink);
    wrapper.append(title, artists, explanationEl, links);
    this.resultTarget.append(wrapper);
  }
}
```

(Uses `createElement`/`textContent` rather than `innerHTML` so album/artist/explanation text — ultimately sourced from external Discogs data — can never be interpreted as HTML.)

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/system/recommend_spec.rb`
Expected: PASS (1 example).

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/recommend_controller.js spec/system/recommend_spec.rb
git commit -m "Add recommend Stimulus controller for the happy path"
```

---

## Task 4: Recommend page — error handling

**Files:**
- Modify: `app/javascript/controllers/recommend_controller.js`
- Modify: `spec/system/recommend_spec.rb`

**Interfaces:**
- Consumes: same as Task 3. Additionally the `422`/`400` `{ error }` JSON shape from `POST /recommend` (`app/controllers/recommendations_controller.rb:19-22`).
- Produces: `renderError(message)` — inline error text in the same result panel, replacing any previous content. A rejected/thrown `fetch` renders a generic retry message via the same method.

- [ ] **Step 1: Write the failing system spec**

Add this example inside the existing `RSpec.describe "Recommend page", type: :system, js: true do ... end` block in `spec/system/recommend_spec.rb` (after the happy-path example, before the closing `end`):

```ruby
  it "shows an inline error when no candidates are admitted" do
    pipeline = instance_double(RecommendationPipeline)
    allow(RecommendationPipeline).to receive(:new).and_return(pipeline)
    allow(pipeline).to receive(:call)
      .and_raise(RecommendationPipeline::NoCandidatesError, "no albums matched the query")

    visit "/recommend"
    fill_in "What are you in the mood for?", with: "obscure vibe"
    click_button "Get a recommendation"

    expect(page).to have_content("no albums matched the query")
    expect(page).to have_current_path("/recommend")
  end
```

- [ ] **Step 2: Run the spec to verify the new example fails**

Run: `bundle exec rspec spec/system/recommend_spec.rb`
Expected: the happy-path example PASSES; the new example FAILS — the current `submit` handler only calls `renderResult` on `ok`, so a `422` response renders nothing and the "no albums matched the query" text never appears.

- [ ] **Step 3: Add error handling to the Stimulus controller**

In `app/javascript/controllers/recommend_controller.js`, replace the `submit` method's `fetch` chain and add `renderError`:

```js
  submit(event) {
    event.preventDefault();
    if (this.requestInFlight) return;

    const query = this.queryTarget.value;
    const genre = this.genreTarget.value.trim();

    const formData = new FormData();
    formData.append("query", query);
    if (genre !== "") formData.append("genre", genre);

    const headers = {};
    const csrfToken = document.querySelector(
      'meta[name="csrf-token"]',
    )?.content;
    if (csrfToken) headers["X-CSRF-Token"] = csrfToken;

    this.requestInFlight = true;
    this.submitTarget.disabled = true;

    fetch("/recommend", { method: "POST", headers, body: formData })
      .then((response) => response.json().then((body) => ({ ok: response.ok, body })))
      .then(({ ok, body }) => {
        if (ok) {
          this.renderResult(body);
        } else {
          this.renderError(body.error || "Something went wrong — try again");
        }
      })
      .catch(() => this.renderError("Something went wrong — try again"))
      .finally(() => {
        this.requestInFlight = false;
        this.submitTarget.disabled = false;
      });
  }
```

Add `renderError` as a new method alongside `renderResult`:

```js
  renderError(message) {
    this.resultTarget.textContent = "";

    const errorEl = document.createElement("p");
    errorEl.className = "text-red-600";
    errorEl.textContent = message;
    this.resultTarget.append(errorEl);
  }
```

- [ ] **Step 4: Run the spec to verify both examples pass**

Run: `bundle exec rspec spec/system/recommend_spec.rb`
Expected: PASS (2 examples).

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/recommend_controller.js spec/system/recommend_spec.rb
git commit -m "Handle inline and network errors on the recommend page"
```

---

## Task 5: Sidebar nav link

**Files:**
- Modify: `app/views/shared/_sidebar.html.erb`
- Modify: `spec/requests/library_spec.rb`

**Interfaces:**
- Consumes: `recommend_path` (from Task 1).
- Produces: a "Recommend" nav `<li>` between the existing "Vibe Map" and "Feedback" entries.

- [ ] **Step 1: Update the failing-first request spec**

In `spec/requests/library_spec.rb`, replace the existing `"shows a Vibe Map nav link positioned between Library and Feedback"` example with:

```ruby
  it "shows nav links positioned Library < Vibe Map < Recommend < Feedback" do
    get "/library"

    body = response.body
    library_link_index = body.index(%(href="/library"))
    vibe_map_link_index = body.index(%(href="/vibe_map"))
    recommend_link_index = body.index(%(href="/recommend"))
    feedback_link_index = body.index(%(href="/feedback"))

    expect(vibe_map_link_index).to be_present
    expect(recommend_link_index).to be_present
    expect(library_link_index).to be < vibe_map_link_index
    expect(vibe_map_link_index).to be < recommend_link_index
    expect(recommend_link_index).to be < feedback_link_index
  end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/requests/library_spec.rb`
Expected: FAIL — `recommend_link_index` is `nil` (`href="/recommend"` doesn't exist in the sidebar yet), so `be_present` fails.

- [ ] **Step 3: Add the sidebar link**

In `app/views/shared/_sidebar.html.erb`, insert a new `<li>` between the "Vibe Map" `<li>` (ending `<%= link_to vibe_map_path ... %>`) and the "Feedback" `<li>`:

```erb
        <li>
          <%= link_to recommend_path, class: "flex items-center p-2 text-gray-900 rounded-lg dark:text-white hover:bg-gray-100 dark:hover:bg-gray-700 group" do %>
            <svg class="w-6 h-6 text-gray-500 transition duration-75 dark:text-gray-400 group-hover:text-gray-900 dark:group-hover:text-white" aria-hidden="true" fill="currentColor" viewBox="0 0 20 20" xmlns="http://www.w3.org/2000/svg"><path d="M5 2a1 1 0 011 1v1h1a1 1 0 010 2H6v1a1 1 0 01-2 0V6H3a1 1 0 010-2h1V3a1 1 0 011-1zm0 10a1 1 0 011 1v1h1a1 1 0 110 2H6v1a1 1 0 11-2 0v-1H3a1 1 0 110-2h1v-1a1 1 0 011-1zM12 2a1 1 0 01.967.744L14.146 7.2 17.5 8.134a1 1 0 010 1.732l-3.354.934-1.18 4.455a1 1 0 01-1.933 0L9.854 10.8 6.5 9.866a1 1 0 010-1.732l3.354-.934 1.18-4.455A1 1 0 0112 2z"></path></svg>
            <span class="ms-3">Recommend</span>
          <% end %>
        </li>
```

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/requests/library_spec.rb`
Expected: PASS.

- [ ] **Step 5: Run the full suite to confirm no regressions**

Run: `bundle exec rspec`
Expected: all examples PASS, including `spec/requests/recommend_spec.rb`, `spec/requests/feedback_spec.rb`, `spec/system/recommend_spec.rb`, `spec/requests/library_spec.rb`, and every pre-existing spec.

- [ ] **Step 6: Commit**

```bash
git add app/views/shared/_sidebar.html.erb spec/requests/library_spec.rb
git commit -m "Add Recommend link to the sidebar nav"
```

---

## Self-Review

**Spec coverage:**
- New route/controller/view → Task 1.
- Stimulus fetch to `/recommend`, CSRF header pattern, result rendering (album, artists, explanation, album link, feedback link) → Task 3.
- `400`/`422` inline error, network failure generic message, double-submit guard (submit disabled for the duration of the fetch) → Task 4.
- `FeedbackController#index` additive param + fallback rules → Task 2.
- Sidebar entry → Task 5.
- Request spec for `GET /recommend` → Task 1. Request specs for `FeedbackController#index` (own pending, other user's event, non-pending event, no param) → Task 2. System spec for the full happy-path flow → Task 3. System spec for the error path → Task 4.
- Out-of-scope items (no pipeline/controller/contract changes, no genre picker, no result history, no outcome-scoring changes, no Turbo Stream response) are respected: no file in this plan touches `RecommendationPipeline`, `RecommendationsController`, `AlbumAffinity`, or `ArtistCooldown`, and the genre field is a plain text input.

**Placeholder scan:** no TBD/TODO markers; every step has complete, runnable code.

**Type consistency:** Stimulus target names (`query`, `genre`, `submit`, `result`) are defined once in Task 1's view and referenced identically in Task 3/4's `static targets`. The `RecommendationPipeline::Result` struct fields (`album`, `explanation`, `recommendation_event`) match the model exactly. The JSON response shape (`recommendation_event_id`, `album: { id, title, artists, genres }`, `explanation`) matches `RecommendationsController#create` exactly and is destructured identically in `renderResult`.
