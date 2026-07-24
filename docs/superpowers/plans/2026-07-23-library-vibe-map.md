# Library Redesign + Vibe Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Library page a readable table view and add a new library-wide Vibe Map page that plots every grounded album's mood as a draggable, clickable dot — the everynoise-style spatial browsing view the original product vision called for.

**Architecture:** A new deterministic `MoodVectors::VibePhraseBuilder` turns a `MoodVector`'s (or `VibeOverride`'s) six mood floats into a short adjective phrase with no LLM involved. `VibeMapController` loads the current user's grounded collection albums, resolves each album's `VibeOverride`-or-`MoodVector` mood snapshot, and hands the view a plain `Dot` struct per album. A new `library_vibe_map_controller.js` Stimulus controller distinguishes a click (navigate to the album) from a drag (reposition + POST an override) on each dot, reusing the existing `POST /albums/:id/vibe_override` endpoint. The Library page becomes a sorted table, and the sidebar gets a new nav entry.

**Tech Stack:** Rails 8.1.3, ERB + Tailwind utility classes, Stimulus via importmap (no JS bundler/npm test runner), RSpec + FactoryBot + Capybara (`rack_test` for plain system specs, headless Chrome via Selenium for `js: true` specs).

**Full design spec:** `docs/superpowers/specs/2026-07-23-library-vibe-map-design.md`

## Global Constraints

- No new database migrations — `MoodVector`, `VibeOverride`, and `Album` already have every column this feature needs.
- New domain-logic classes go in `app/models/<pluralized_model>/`, e.g. `MoodVectors::VibePhraseBuilder` — this repo's forward-looking SRP convention (existing flat classes like `CandidateRetrieval` predate it and are not touched).
- Override precedence: whenever a `VibeOverride` exists for the current user + album, its 6 mood values (not the raw `MoodVector`) feed both the vibe phrase and the plotted map position.
- Ungrounded albums (`enrichment_status != "grounded"`) never appear on the Vibe Map; they still appear as rows in the redesigned Library table.
- The Vibe Map reveals a vibe phrase only on hover/focus (via the dot's `title` attribute), never as permanently-rendered text — a deliberate v1 simplification vs. true everynoise-style always-on labels.
- A plain click (no pointer movement) on a dot navigates to the album; a drag past a small pixel threshold repositions the dot and, on release, posts a `VibeOverride` with recomputed `valence`/`arousal` and the album's *current* `danceability`/`mood_acoustic`/`mood_relaxed`/`mood_happy` (override if present, else `MoodVector`) — never hardcoded `0.5`, unlike the existing per-album `vibe_map_controller.js`.
- `app/views/albums/_vibe_map.html.erb` and `app/javascript/controllers/vibe_map_controller.js` (the existing single-album map) are untouched by this work.
- Out of scope: running `EnrichAlbumJob` against the real collection, always-on collision-avoided text labels, and wiring `VibeOverride` into `CandidateRetrieval`'s scoring.

---

## Task 1: `MoodVectors::VibePhraseBuilder`

**Files:**
- Create: `app/models/mood_vectors/vibe_phrase_builder.rb`
- Modify: `app/models/mood_vector.rb`
- Test: `spec/models/mood_vectors/vibe_phrase_builder_spec.rb`
- Modify: `spec/models/mood_vector_spec.rb`

**Interfaces:**
- Produces: `MoodVectors::VibePhraseBuilder.new(mood, genre: nil).call` — `mood` is duck-typed (anything responding to `valence`, `arousal`, `danceability`, `mood_acoustic`, `mood_relaxed`, `mood_happy`; both `MoodVector` and `VibeOverride` qualify since they share that exact column set). Returns a `String` (never `nil`). Also `MoodVector#vibe_phrase(genre: nil)`.

- [ ] **Step 1: Create the directory and write the failing spec**

Run: `mkdir -p app/models/mood_vectors spec/models/mood_vectors`

Create `spec/models/mood_vectors/vibe_phrase_builder_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe MoodVectors::VibePhraseBuilder do
  def mood(**overrides)
    MoodVector.new(
      valence: 0.5, arousal: 0.5, danceability: 0.5, mood_acoustic: 0.5, mood_relaxed: 0.5, mood_happy: 0.5,
      **overrides
    )
  end

  it "excludes a head sitting exactly at the neutral midpoint" do
    expect(described_class.new(mood(valence: 0.5)).call).to eq("")
  end

  it "excludes a head at the low/mid boundary (0.4 is not distinctive)" do
    expect(described_class.new(mood(valence: 0.4)).call).to eq("")
  end

  it "includes a head just below the low boundary as the low-band adjective" do
    expect(described_class.new(mood(valence: 0.39)).call).to eq("somber")
  end

  it "excludes a head at the high/mid boundary (0.6 is not distinctive)" do
    expect(described_class.new(mood(valence: 0.6)).call).to eq("")
  end

  it "includes a head just above the high boundary as the high-band adjective" do
    expect(described_class.new(mood(valence: 0.61)).call).to eq("sunny")
  end

  it "selects only the 2 most distinctive heads out of several distinctive ones" do
    phrase_mood = mood(valence: 0.2, arousal: 0.35, mood_happy: 0.1)
    expect(described_class.new(phrase_mood).call).to eq("brooding somber")
  end

  it "joins the selected adjectives with the album's genre" do
    phrase_mood = mood(valence: 0.2, arousal: 0.35, mood_happy: 0.1)
    expect(described_class.new(phrase_mood, genre: "Jazz").call).to eq("brooding somber — Jazz")
  end

  it "falls back to the genre alone when nothing is distinctive" do
    expect(described_class.new(mood, genre: "Techno").call).to eq("Techno")
  end

  it "falls back to a single adjective (no separator) when only one head is distinctive" do
    expect(described_class.new(mood(valence: 0.2), genre: "Techno").call).to eq("somber — Techno")
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/models/mood_vectors/vibe_phrase_builder_spec.rb`
Expected: FAIL — `NameError: uninitialized constant MoodVectors` (or similar), since the class doesn't exist yet.

- [ ] **Step 3: Write the implementation**

Create `app/models/mood_vectors/vibe_phrase_builder.rb`:

```ruby
module MoodVectors
  class VibePhraseBuilder
    ADJECTIVES = {
      valence: { low: "somber", high: "sunny" },
      arousal: { low: "hushed", high: "driving" },
      danceability: { low: "static", high: "danceable" },
      mood_acoustic: { low: "electric", high: "acoustic" },
      mood_relaxed: { low: "tense", high: "mellow" },
      mood_happy: { low: "brooding", high: "joyful" }
    }.freeze

    NEUTRAL = 0.5
    DISTINCTIVE_THRESHOLD = 0.1

    def initialize(mood, genre: nil)
      @mood = mood
      @genre = genre
    end

    def call
      adjectives = distinctive_heads.first(2).map { |head| adjective_for(head) }
      [ adjectives.join(" "), @genre ].select(&:present?).join(" — ")
    end

    private

    def distinctive_heads
      MoodVector::MOOD_HEADS.each_with_index
        .select { |head, _index| distance(head) > DISTINCTIVE_THRESHOLD }
        .sort_by { |head, index| [ -distance(head), index ] }
        .map(&:first)
    end

    def distance(head)
      (@mood.send(head) - NEUTRAL).abs
    end

    def adjective_for(head)
      band = @mood.send(head) > 0.6 ? :high : :low
      ADJECTIVES.fetch(head).fetch(band)
    end
  end
end
```

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/models/mood_vectors/vibe_phrase_builder_spec.rb`
Expected: PASS (9 examples, 0 failures)

- [ ] **Step 5: Add the `MoodVector` delegating method and its failing test**

In `spec/models/mood_vector_spec.rb`, add this example inside the existing `RSpec.describe MoodVector, type: :model do` block, right before the final `end`:

```ruby

  it "delegates vibe_phrase to MoodVectors::VibePhraseBuilder" do
    mood_vector = MoodVector.new(album: album, valence: 0.2, arousal: 0.35, mood_happy: 0.1)
    expect(mood_vector.vibe_phrase(genre: "Jazz")).to eq("brooding somber — Jazz")
  end
```

Run: `bundle exec rspec spec/models/mood_vector_spec.rb`
Expected: FAIL — `NoMethodError: undefined method 'vibe_phrase'`

- [ ] **Step 6: Implement the delegating method**

In `app/models/mood_vector.rb`, add this method right after `distance_to`:

```ruby
  def vibe_phrase(genre: nil)
    MoodVectors::VibePhraseBuilder.new(self, genre: genre).call
  end
```

- [ ] **Step 7: Run the spec to verify it passes**

Run: `bundle exec rspec spec/models/mood_vector_spec.rb`
Expected: PASS (5 examples, 0 failures)

- [ ] **Step 8: Commit**

```bash
git add app/models/mood_vectors/vibe_phrase_builder.rb app/models/mood_vector.rb \
  spec/models/mood_vectors/vibe_phrase_builder_spec.rb spec/models/mood_vector_spec.rb
git commit -m "Add MoodVectors::VibePhraseBuilder and MoodVector#vibe_phrase"
```

---

## Task 2: `VibeMapController`, route, and view

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/vibe_map_controller.rb`
- Create: `app/views/vibe_map/index.html.erb`
- Test: `spec/requests/vibe_map_spec.rb`

**Interfaces:**
- Consumes: `MoodVectors::VibePhraseBuilder` (Task 1); `VibeOverride`, `MoodVector`, `Album.grounded` (existing).
- Produces: `GET /vibe_map` (`vibe_map_path`); `VibeMapController::Dot` struct (`album`, `valence`, `arousal`, `danceability`, `mood_acoustic`, `mood_relaxed`, `mood_happy`, `phrase`) exposed to the view as `@dots`. The view renders one container `div.vibe-map-canvas` (`data-controller="library-vibe-map"`, `data-library-vibe-map-target="map"`) holding one `div.vibe-map-dot` per dot, each carrying `data-action="mousedown->library-vibe-map#dotMouseDown"` plus `data-href`, `data-album-id`, `data-genre`, `data-danceability`, `data-mood-acoustic`, `data-mood-relaxed`, `data-mood-happy` — Task 3's Stimulus controller reads these exact attribute names.

- [ ] **Step 1: Add the route**

In `config/routes.rb`, change:

```ruby
  root "library#index"
  get "library" => "library#index", as: :library
```

to:

```ruby
  root "library#index"
  get "library" => "library#index", as: :library
  get "vibe_map" => "vibe_map#index", as: :vibe_map
```

- [ ] **Step 2: Write the failing request spec**

Create `spec/requests/vibe_map_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "GET /vibe_map", type: :request do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  it "shows only the current user's grounded albums" do
    grounded = create(:album, :grounded)
    create(:mood_vector, album: grounded, valence: 0.7, arousal: 0.3)
    CollectionItem.create!(user: user, album: grounded, release_id: 1)

    get "/vibe_map"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(data-album-id="#{grounded.id}"))
  end

  it "excludes another user's collection albums" do
    other_user = create(:user)
    other_album = create(:album, :grounded)
    create(:mood_vector, album: other_album)
    CollectionItem.create!(user: other_user, album: other_album, release_id: 2)

    get "/vibe_map"

    expect(response.body).not_to include(%(data-album-id="#{other_album.id}"))
  end

  it "excludes ungrounded albums from the current user's own collection" do
    pending_album = create(:album)
    CollectionItem.create!(user: user, album: pending_album, release_id: 3)

    get "/vibe_map"

    expect(response.body).not_to include(%(data-album-id="#{pending_album.id}"))
  end
end
```

- [ ] **Step 3: Run the spec to verify it fails**

Run: `bundle exec rspec spec/requests/vibe_map_spec.rb`
Expected: FAIL — `ActionController::RoutingError` or `uninitialized constant VibeMapController`

- [ ] **Step 4: Write the controller**

Create `app/controllers/vibe_map_controller.rb`:

```ruby
class VibeMapController < ApplicationController
  Dot = Struct.new(
    :album, :valence, :arousal, :danceability, :mood_acoustic, :mood_relaxed, :mood_happy, :phrase,
    keyword_init: true
  )

  def index
    collection_items = Current.user.collection_items
      .joins(:album)
      .merge(Album.grounded)
      .includes(album: :mood_vector)

    albums = collection_items.map(&:album)
    overrides = VibeOverride.where(user: Current.user, album_id: albums.map(&:id)).index_by(&:album_id)

    @dots = albums.map do |album|
      mood = overrides[album.id] || album.mood_vector
      genre = album.genres.first

      Dot.new(
        album: album,
        valence: mood.valence,
        arousal: mood.arousal,
        danceability: mood.danceability,
        mood_acoustic: mood.mood_acoustic,
        mood_relaxed: mood.mood_relaxed,
        mood_happy: mood.mood_happy,
        phrase: MoodVectors::VibePhraseBuilder.new(mood, genre: genre).call
      )
    end
  end
end
```

- [ ] **Step 5: Write the view**

Create `app/views/vibe_map/index.html.erb`:

```erb
<h1 class="text-2xl font-bold mb-4">Vibe Map</h1>

<div
  data-controller="library-vibe-map"
  data-library-vibe-map-target="map"
  class="vibe-map-canvas relative w-full max-w-3xl aspect-square border border-gray-300 rounded-lg bg-gray-50"
>
  <% @dots.each do |dot| %>
    <div
      class="vibe-map-dot absolute w-3 h-3 -translate-x-1/2 -translate-y-1/2 rounded-full bg-indigo-600 cursor-pointer hover:ring-2 hover:ring-indigo-300"
      style="left: <%= (dot.valence * 100).round(2) %>%; top: <%= ((1 - dot.arousal) * 100).round(2) %>%;"
      title="<%= dot.phrase %>"
      tabindex="0"
      data-action="mousedown->library-vibe-map#dotMouseDown"
      data-href="<%= album_path(dot.album) %>"
      data-album-id="<%= dot.album.id %>"
      data-genre="<%= dot.album.genres.first %>"
      data-danceability="<%= dot.danceability %>"
      data-mood-acoustic="<%= dot.mood_acoustic %>"
      data-mood-relaxed="<%= dot.mood_relaxed %>"
      data-mood-happy="<%= dot.mood_happy %>"
    ></div>
  <% end %>
</div>
```

- [ ] **Step 6: Run the spec to verify it passes**

Run: `bundle exec rspec spec/requests/vibe_map_spec.rb`
Expected: PASS (3 examples, 0 failures)

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/controllers/vibe_map_controller.rb app/views/vibe_map/index.html.erb \
  spec/requests/vibe_map_spec.rb
git commit -m "Add the library-wide Vibe Map page"
```

---

## Task 3: `library_vibe_map_controller.js` (click vs. drag)

**Files:**
- Create: `app/javascript/controllers/library_vibe_map_controller.js`
- Test: `spec/system/vibe_map_spec.rb`

**Interfaces:**
- Consumes: the `data-controller="library-vibe-map"` / `data-library-vibe-map-target="map"` container and per-dot `data-action`, `data-href`, `data-album-id`, `data-genre`, `data-danceability`, `data-mood-acoustic`, `data-mood-relaxed`, `data-mood-happy` attributes from Task 2's view.
- Produces: on a plain click, `Turbo.visit(dataset.href)`. On a drag past 4px, live-repositions the dot and `POST`s to `/albums/:id/vibe_override` with `source: "vibe_map"`, recomputed `valence`/`arousal`, and the carried-over `danceability`/`mood_acoustic`/`mood_relaxed`/`mood_happy`; on a successful response adds the `vibe-map-dot--saved` class to the dot (mirrors the existing `vibe-map--saved` marker convention in `app/javascript/controllers/vibe_map_controller.js`, giving system specs a reliable `have_css` wait point).

- [ ] **Step 1: Write the failing system spec**

Create `spec/system/vibe_map_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Vibe Map", type: :system, js: true do
  let(:user) { create(:user) }
  let(:album) { create(:album, :grounded, title: "Kind of Blue", genres: [ "Jazz" ]) }

  before do
    create(
      :mood_vector, album: album,
      valence: 0.7, arousal: 0.3, danceability: 0.2, mood_acoustic: 0.9, mood_relaxed: 0.1, mood_happy: 0.8
    )
    CollectionItem.create!(user: user, album: album, release_id: 1)
    sign_in_as(user)
  end

  it "renders a dot at the position derived from the album's mood values" do
    visit vibe_map_path

    dot = find(".vibe-map-dot")
    expect(dot[:style]).to include("left: 70.0%")
    expect(dot[:style]).to include("top: 70.0%")
  end

  it "navigates to the album when a dot is clicked without dragging" do
    visit vibe_map_path

    find(".vibe-map-dot").click

    expect(page).to have_current_path(album_path(album))
  end

  it "posts an override with the new position and preserves the other mood values on drag" do
    visit vibe_map_path

    find(".vibe-map-dot").drag_to(find(".vibe-map-canvas"))

    expect(page).to have_css(".vibe-map-dot--saved")

    override = VibeOverride.find_by(user: user, album: album)
    expect(override.source).to eq("vibe_map")
    expect(override.valence).to be_within(0.05).of(0.5)
    expect(override.arousal).to be_within(0.05).of(0.5)
    expect(override.danceability).to eq(0.2)
    expect(override.mood_acoustic).to eq(0.9)
    expect(override.mood_relaxed).to eq(0.1)
    expect(override.mood_happy).to eq(0.8)
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/system/vibe_map_spec.rb`
Expected: FAIL — the first example fails because nothing yet handles `mousedown` (no repositioning), the click example times out waiting for navigation, and the drag example never finds `.vibe-map-dot--saved`.

- [ ] **Step 3: Write the Stimulus controller**

Create `app/javascript/controllers/library_vibe_map_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

const DRAG_THRESHOLD_PX = 4

export default class extends Controller {
  static targets = ["map"]

  connect() {
    this.boundMouseMove = this.onMouseMove.bind(this)
    this.boundMouseUp = this.onMouseUp.bind(this)
  }

  dotMouseDown(event) {
    const dot = event.currentTarget
    this.dragging = {
      dot,
      moved: false,
      startX: event.clientX,
      startY: event.clientY,
      href: dot.dataset.href,
      albumId: dot.dataset.albumId,
      genre: dot.dataset.genre,
      danceability: dot.dataset.danceability,
      moodAcoustic: dot.dataset.moodAcoustic,
      moodRelaxed: dot.dataset.moodRelaxed,
      moodHappy: dot.dataset.moodHappy,
      valence: null,
      arousal: null
    }
    document.addEventListener("mousemove", this.boundMouseMove)
    document.addEventListener("mouseup", this.boundMouseUp)
    event.preventDefault()
  }

  onMouseMove(event) {
    if (!this.dragging) return

    const dx = event.clientX - this.dragging.startX
    const dy = event.clientY - this.dragging.startY
    if (!this.dragging.moved && Math.hypot(dx, dy) > DRAG_THRESHOLD_PX) {
      this.dragging.moved = true
    }
    if (!this.dragging.moved) return

    const bounds = this.mapTarget.getBoundingClientRect()
    const x = Math.min(Math.max((event.clientX - bounds.left) / bounds.width, 0), 1)
    const y = Math.min(Math.max((event.clientY - bounds.top) / bounds.height, 0), 1)

    this.dragging.dot.style.left = `${x * 100}%`
    this.dragging.dot.style.top = `${y * 100}%`
    this.dragging.valence = x
    this.dragging.arousal = 1 - y
  }

  onMouseUp() {
    document.removeEventListener("mousemove", this.boundMouseMove)
    document.removeEventListener("mouseup", this.boundMouseUp)

    const state = this.dragging
    this.dragging = null
    if (!state) return

    if (state.moved) {
      this.saveOverride(state)
    } else {
      Turbo.visit(state.href)
    }
  }

  saveOverride(state) {
    const formData = new FormData()
    formData.append("valence", state.valence)
    formData.append("arousal", state.arousal)
    formData.append("danceability", state.danceability)
    formData.append("mood_acoustic", state.moodAcoustic)
    formData.append("mood_relaxed", state.moodRelaxed)
    formData.append("mood_happy", state.moodHappy)
    formData.append("genre", state.genre || "")
    formData.append("source", "vibe_map")

    const headers = {}
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (csrfToken) headers["X-CSRF-Token"] = csrfToken

    fetch(`/albums/${state.albumId}/vibe_override`, {
      method: "POST",
      headers,
      body: formData
    }).then((response) => {
      if (response.ok) state.dot.classList.add("vibe-map-dot--saved")
    })
  }
}
```

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/system/vibe_map_spec.rb`
Expected: PASS (3 examples, 0 failures)

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/library_vibe_map_controller.js spec/system/vibe_map_spec.rb
git commit -m "Add drag-vs-click handling to the Vibe Map"
```

---

## Task 4: Library page redesign (table)

**Files:**
- Modify: `app/controllers/library_controller.rb`
- Modify: `app/views/library/index.html.erb`
- Create: `app/helpers/library_helper.rb`
- Test: `spec/requests/library_spec.rb`

**Interfaces:**
- Produces: `LibraryHelper#status_badge_class(enrichment_status)` — returns a Tailwind class string for a given `Album#enrichment_status` value.

- [ ] **Step 1: Write the failing request spec**

Create `spec/requests/library_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "GET /library", type: :request do
  let(:user) { create(:user, discogs_username: "listener") }

  before { sign_in_as(user) }

  it "lists the current user's collection as a table sorted by artist then title" do
    zebra = create(:album, artists: [ "Zebra Band" ], title: "Zebra Album", genres: [ "Rock" ], year: 2010, enrichment_status: "pending")
    apple = create(:album, artists: [ "Apple Band" ], title: "Apple Album", genres: [ "Jazz" ], year: 2015, enrichment_status: "grounded")
    CollectionItem.create!(user: user, album: zebra, release_id: 1)
    CollectionItem.create!(user: user, album: apple, release_id: 2)

    get "/library"

    expect(response).to have_http_status(:ok)
    expect(response.body.index("Apple Album")).to be < response.body.index("Zebra Album")
    expect(response.body).to include("Jazz")
    expect(response.body).to include("Rock")
    expect(response.body).to include("2010")
    expect(response.body).to include("2015")
    expect(response.body).to include("Grounded")
    expect(response.body).to include("Pending")
  end

  it "shows the Connect Discogs prompt when no Discogs account is linked" do
    unlinked_user = create(:user, discogs_username: nil)
    sign_in_as(unlinked_user)

    get "/library"

    expect(response.body).to include("Connect Discogs")
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/requests/library_spec.rb`
Expected: FAIL — the sort-order and status-text expectations fail against the current plain `<ul>` markup (no "Grounded"/"Pending" text, no guaranteed sort order).

- [ ] **Step 3: Write the helper**

Create `app/helpers/library_helper.rb`:

```ruby
module LibraryHelper
  STATUS_BADGE_CLASSES = {
    "pending" => "bg-gray-100 text-gray-700",
    "matching_audio" => "bg-yellow-100 text-yellow-700",
    "extracting_features" => "bg-yellow-100 text-yellow-700",
    "grounded" => "bg-green-100 text-green-700",
    "failed" => "bg-red-100 text-red-700"
  }.freeze

  def status_badge_class(enrichment_status)
    STATUS_BADGE_CLASSES.fetch(enrichment_status, "bg-gray-100 text-gray-700")
  end
end
```

- [ ] **Step 4: Update the controller**

Replace the contents of `app/controllers/library_controller.rb`:

```ruby
class LibraryController < ApplicationController
  def index
    @collection_items = Current.user.collection_items
      .includes(:album)
      .joins(:album)
      .order("albums.artists ASC, albums.title ASC")
  end
end
```

- [ ] **Step 5: Update the view**

Replace the contents of `app/views/library/index.html.erb`:

```erb
<h1 class="text-2xl font-bold mb-4">Library</h1>

<% if Current.user.discogs_username.blank? %>
  <%= link_to "Connect Discogs", new_discogs_connection_path, class: "text-blue-600 underline" %>
<% else %>
  <table class="w-full text-left text-sm">
    <thead>
      <tr class="border-b border-gray-200">
        <th class="py-2 pr-4">Title</th>
        <th class="py-2 pr-4">Artists</th>
        <th class="py-2 pr-4">Year</th>
        <th class="py-2 pr-4">Genres</th>
        <th class="py-2 pr-4">Status</th>
      </tr>
    </thead>
    <tbody>
      <% @collection_items.each do |item| %>
        <% album = item.album %>
        <tr class="border-b border-gray-100">
          <td class="py-2 pr-4"><%= link_to album.title, album_path(album), class: "text-blue-600 underline" %></td>
          <td class="py-2 pr-4"><%= album.artists.join(", ") %></td>
          <td class="py-2 pr-4"><%= album.year %></td>
          <td class="py-2 pr-4">
            <% album.genres.each do |genre| %>
              <span class="inline-block px-2 py-0.5 mr-1 mb-1 rounded-full bg-gray-100 text-gray-700 text-xs"><%= genre %></span>
            <% end %>
          </td>
          <td class="py-2 pr-4">
            <span class="<%= status_badge_class(album.enrichment_status) %> px-2 py-0.5 rounded-full text-xs">
              <%= album.enrichment_status.titleize %>
            </span>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
<% end %>
```

- [ ] **Step 6: Run the spec to verify it passes**

Run: `bundle exec rspec spec/requests/library_spec.rb`
Expected: PASS (2 examples, 0 failures)

- [ ] **Step 7: Run the Discogs connection system spec for regressions**

Run: `bundle exec rspec spec/system/discogs_connection_spec.rb`
Expected: PASS (1 example, 0 failures) — it only asserts `have_content("Album One")`, which the table still satisfies.

- [ ] **Step 8: Commit**

```bash
git add app/controllers/library_controller.rb app/views/library/index.html.erb \
  app/helpers/library_helper.rb spec/requests/library_spec.rb
git commit -m "Redesign the Library page as a sorted table"
```

---

## Task 5: Sidebar nav entry

**Files:**
- Modify: `app/views/shared/_sidebar.html.erb`
- Modify: `spec/requests/library_spec.rb`

**Interfaces:**
- Consumes: `vibe_map_path` (Task 2).

- [ ] **Step 1: Add the failing nav-order test**

In `spec/requests/library_spec.rb`, add this example inside the existing `RSpec.describe "GET /library", type: :request do` block, right before the final `end`:

```ruby

  it "shows a Vibe Map nav link positioned between Library and Feedback" do
    get "/library"

    body = response.body
    library_link_index = body.index(%(href="/library"))
    vibe_map_link_index = body.index(%(href="/vibe_map"))
    feedback_link_index = body.index(%(href="/feedback"))

    expect(vibe_map_link_index).to be_present
    expect(library_link_index).to be < vibe_map_link_index
    expect(vibe_map_link_index).to be < feedback_link_index
  end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/requests/library_spec.rb`
Expected: FAIL — `vibe_map_link_index` is `nil` since no `href="/vibe_map"` exists in the sidebar yet.

- [ ] **Step 3: Add the nav item**

In `app/views/shared/_sidebar.html.erb`, insert a new `<li>` between the existing Library `<li>` and the Feedback `<li>` (i.e., right after the Library `<li>`'s closing `</li>` on line 27, before the Feedback `<li>` starts on line 28):

```erb
        <li>
          <%= link_to vibe_map_path, class: "flex items-center p-2 text-gray-900 rounded-lg dark:text-white hover:bg-gray-100 dark:hover:bg-gray-700 group" do %>
            <svg class="w-6 h-6 text-gray-500 transition duration-75 dark:text-gray-400 group-hover:text-gray-900 dark:group-hover:text-white" aria-hidden="true" fill="currentColor" viewBox="0 0 20 20" xmlns="http://www.w3.org/2000/svg"><path fill-rule="evenodd" d="M9.69 18.933l.003.001C9.89 19.02 10 19 10 19s.11.02.308-.066l.002-.001.006-.003.018-.008a5.741 5.741 0 00.281-.14c.186-.096.446-.24.757-.433.62-.384 1.445-.966 2.274-1.765C15.302 14.988 17 12.493 17 9A7 7 0 103 9c0 3.492 1.698 5.988 3.355 7.584a13.731 13.731 0 002.273 1.765 11.842 11.842 0 00.976.544l.062.029.018.008.006.003zM10 11.25a2.25 2.25 0 100-4.5 2.25 2.25 0 000 4.5z" clip-rule="evenodd"></path></svg>
            <span class="ms-3">Vibe Map</span>
          <% end %>
        </li>
```

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/requests/library_spec.rb`
Expected: PASS (3 examples, 0 failures)

- [ ] **Step 5: Run the full test suite for regressions**

Run: `bundle exec rspec`
Expected: PASS, 0 failures

- [ ] **Step 6: Commit**

```bash
git add app/views/shared/_sidebar.html.erb spec/requests/library_spec.rb
git commit -m "Add Vibe Map to the sidebar nav"
```
