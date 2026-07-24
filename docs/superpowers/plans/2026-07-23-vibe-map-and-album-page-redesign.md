# Vibe Map & Album Page Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rescale the library-wide Vibe Map so albums spread across the full canvas and show an always-on title label per dot, and expand the album detail page with header metadata, a full 6-dimension mood breakdown, a rendered vibe card, and numeric mood coordinates.

**Architecture:** Server-side min-max rescaling computed once in `VibeMapController#index` (exposed to the view as precomputed `x_percent`/`y_percent` per dot, and as data attributes for the client); the Stimulus drag controller inverts the same transform before persisting an override. The album page gains three new server-rendered sections driven by data that already exists (`MoodVector`/`VibeOverride`/`VibeCard`) but was never displayed.

**Tech Stack:** Rails 8 views/controllers, Stimulus (`@hotwired/stimulus`), Tailwind CSS utility classes, RSpec (request + system specs), FactoryBot.

## Global Constraints

- No new JS dependencies — plain Tailwind + vanilla Stimulus only (Approach C from the design was explicitly rejected).
- No cover art / Discogs image work — out of scope per the spec.
- These existing specs must keep passing UNCHANGED by the end of this plan: `spec/system/vibe_map_spec.rb`, `spec/system/vibe_map_override_spec.rb`, `spec/requests/vibe_map_spec.rb`.
- Degenerate-axis rule: when an axis has no spread (`min == max`), skip rescaling for that axis entirely (use the raw value) — do not center at 50%. This is required, not just tidy, to keep the existing single-album system spec passing.
- Library map on-canvas label shows the album **title only** — no artist/genre inline (those stay on the existing hover tooltip).
- Mood-breakdown / stat-bar accent color is `indigo-600`, matching the existing dot color — no new palette.
- The always-on label on the library map is decorative only (`pointer-events-none`): it does **not** expand the click/drag hit target beyond the existing 12px dot. This is a deliberate simplification made during planning (the brainstormed "bigger hit target" nicety turned out to require either a positioning wrapper that breaks the existing pixel-exact-position system spec, or fragile duplicate event bindings — not worth the risk for a cosmetic improvement). Flag this to the user when the plan is presented.

---

### Task 1: Rescale Vibe Map dot positions + always-on title labels

**Files:**
- Modify: `app/controllers/vibe_map_controller.rb`
- Modify: `app/views/vibe_map/index.html.erb`
- Modify: `spec/requests/vibe_map_spec.rb`

**Interfaces:**
- Consumes: nothing new (uses existing `Album.grounded`, `VibeOverride`, `MoodVector`, `MoodVectors::VibePhraseBuilder`).
- Produces: `VibeMapController::Dot` struct gains `x_percent`/`y_percent` (Float, 0..100, already display-scaled). Controller sets `@valence_min`, `@valence_max`, `@arousal_min`, `@arousal_max` (Float) instance variables, rendered as `data-library-vibe-map-valence-min-value` / `-valence-max-value` / `-arousal-min-value` / `-arousal-max-value` on the `.vibe-map-canvas` element — Task 2's JS consumes these exact attribute names.

- [ ] **Step 1: Write the failing requests specs**

Add to the end of `spec/requests/vibe_map_spec.rb` (inside the existing `RSpec.describe` block, after the last `it`):

```ruby
  it "rescales dot positions to fill the display range when a spread exists" do
    low = create(:album, :grounded, title: "Low")
    high = create(:album, :grounded, title: "High")
    create(:mood_vector, album: low, valence: 0.2, arousal: 0.2)
    create(:mood_vector, album: high, valence: 0.8, arousal: 0.8)
    CollectionItem.create!(user: user, album: low, release_id: 10)
    CollectionItem.create!(user: user, album: high, release_id: 11)

    get "/vibe_map"

    expect(response.body).to match(/left:\s*0\.0%/)
    expect(response.body).to match(/left:\s*100\.0%/)
  end

  it "rescales only the axis that actually has spread" do
    low_valence = create(:album, :grounded)
    high_valence = create(:album, :grounded)
    create(:mood_vector, album: low_valence, valence: 0.3, arousal: 0.5)
    create(:mood_vector, album: high_valence, valence: 0.9, arousal: 0.5)
    CollectionItem.create!(user: user, album: low_valence, release_id: 12)
    CollectionItem.create!(user: user, album: high_valence, release_id: 13)

    get "/vibe_map"

    # valence has real spread (0.3..0.9) -> rescaled to fill 0%..100%
    expect(response.body).to match(/left:\s*0\.0%/)
    expect(response.body).to match(/left:\s*100\.0%/)
    # arousal is identical (0.5) for both -> no rescaling, raw value used: 100 - 0.5*100 = 50.0
    expect(response.body).to match(/top:\s*50\.0%/)
  end

  it "exposes the valence/arousal range as data attributes for the drag controller" do
    low = create(:album, :grounded)
    high = create(:album, :grounded)
    create(:mood_vector, album: low, valence: 0.2, arousal: 0.25)
    create(:mood_vector, album: high, valence: 0.8, arousal: 0.75)
    CollectionItem.create!(user: user, album: low, release_id: 13)
    CollectionItem.create!(user: user, album: high, release_id: 14)

    get "/vibe_map"

    expect(response.body).to include(%(data-library-vibe-map-valence-min-value="0.2"))
    expect(response.body).to include(%(data-library-vibe-map-valence-max-value="0.8"))
    expect(response.body).to include(%(data-library-vibe-map-arousal-min-value="0.25"))
    expect(response.body).to include(%(data-library-vibe-map-arousal-max-value="0.75"))
  end

  it "shows the album title as an always-on label" do
    grounded = create(:album, :grounded, title: "Kind of Blue")
    create(:mood_vector, album: grounded, valence: 0.5, arousal: 0.5)
    CollectionItem.create!(user: user, album: grounded, release_id: 15)

    get "/vibe_map"

    expect(response.body).to include(%(class="vibe-map-label))
    expect(response.body).to include("Kind of Blue")
  end
```

- [ ] **Step 2: Run the new specs to verify they fail**

Run: `bundle exec rspec spec/requests/vibe_map_spec.rb`
Expected: 3 of the 4 new examples FAIL outright (no `x_percent`/`y_percent`, no data attributes, no label markup exist yet). The "rescales only the axis that actually has spread" example fails too, but only on its valence assertions — old code produces `left: 30.0%`/`left: 90.0%` (raw, unscaled) instead of `0.0%`/`100.0%`; its arousal assertion (`top: 50.0%`) would already be satisfied by old code since both albums share the same raw arousal, but the example still fails overall because RSpec requires every expectation in the block to pass. The 3 pre-existing examples still PASS.

- [ ] **Step 3: Implement rescaling in the controller**

Replace `app/controllers/vibe_map_controller.rb` with:

```ruby
class VibeMapController < ApplicationController
  Dot = Struct.new(
    :album, :valence, :arousal, :danceability, :mood_acoustic, :mood_relaxed, :mood_happy, :phrase,
    :x_percent, :y_percent,
    keyword_init: true
  )

  def index
    collection_items = Current.user.collection_items
      .joins(:album)
      .merge(Album.grounded)
      .includes(album: :mood_vector)

    albums = collection_items.map(&:album)
    overrides = VibeOverride.where(user: Current.user, album_id: albums.map(&:id)).index_by(&:album_id)
    moods = albums.index_with { |album| overrides[album.id] || album.mood_vector }

    @valence_min, @valence_max = minmax(moods.values.map(&:valence))
    @arousal_min, @arousal_max = minmax(moods.values.map(&:arousal))

    @dots = albums.map do |album|
      mood = moods[album]
      genre = album.genres.first

      Dot.new(
        album: album,
        valence: mood.valence,
        arousal: mood.arousal,
        danceability: mood.danceability,
        mood_acoustic: mood.mood_acoustic,
        mood_relaxed: mood.mood_relaxed,
        mood_happy: mood.mood_happy,
        phrase: MoodVectors::VibePhraseBuilder.new(mood, genre: genre).call,
        x_percent: rescale(mood.valence, @valence_min, @valence_max),
        y_percent: 100 - rescale(mood.arousal, @arousal_min, @arousal_max)
      )
    end
  end

  private

  def minmax(values)
    return [ 0.0, 1.0 ] if values.empty?

    [ values.min, values.max ]
  end

  def rescale(value, min, max)
    return (value * 100).round(2) if min == max

    (((value - min) / (max - min).to_f) * 100).round(2)
  end
end
```

- [ ] **Step 4: Implement the view changes**

Replace `app/views/vibe_map/index.html.erb` with:

```erb
<h1 class="text-2xl font-bold mb-4">Vibe Map</h1>

<div class="max-w-3xl flex gap-2">
  <div class="flex flex-col justify-between text-xs font-medium text-gray-400 uppercase tracking-wide shrink-0 py-1">
    <span>Energetic</span>
    <span>Calm</span>
  </div>
  <div class="flex-1">
    <div
      data-controller="library-vibe-map"
      data-library-vibe-map-target="map"
      data-library-vibe-map-valence-min-value="<%= @valence_min %>"
      data-library-vibe-map-valence-max-value="<%= @valence_max %>"
      data-library-vibe-map-arousal-min-value="<%= @arousal_min %>"
      data-library-vibe-map-arousal-max-value="<%= @arousal_max %>"
      class="vibe-map-canvas relative w-full aspect-square border border-gray-300 rounded-lg bg-gray-50"
    >
      <% @dots.each do |dot| %>
        <div
          class="vibe-map-dot absolute w-3 h-3 -translate-x-1/2 -translate-y-1/2 rounded-full bg-indigo-600 cursor-pointer hover:ring-2 hover:ring-indigo-300"
          style="left: <%= dot.x_percent %>%; top: <%= dot.y_percent %>%;"
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
        <span
          class="vibe-map-label absolute translate-x-2 -translate-y-1/2 pointer-events-none text-[10px] text-gray-500 whitespace-nowrap overflow-hidden text-ellipsis max-w-[120px]"
          style="left: <%= dot.x_percent %>%; top: <%= dot.y_percent %>%;"
        ><%= dot.album.title %></span>
      <% end %>
    </div>
    <div class="flex justify-between text-xs font-medium text-gray-400 uppercase tracking-wide mt-1">
      <span>Sad</span>
      <span>Happy</span>
    </div>
  </div>
</div>
```

- [ ] **Step 5: Run the full vibe map request spec file to verify all examples pass**

Run: `bundle exec rspec spec/requests/vibe_map_spec.rb`
Expected: 7 examples, 0 failures (3 pre-existing + 4 new).

- [ ] **Step 6: Run the existing system specs to confirm no regression**

Run: `bundle exec rspec spec/system/vibe_map_spec.rb spec/system/vibe_map_override_spec.rb`
Expected: 4 examples, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/vibe_map_controller.rb app/views/vibe_map/index.html.erb spec/requests/vibe_map_spec.rb
git commit -m "Rescale Vibe Map dot positions and add always-on title labels"
```

---

### Task 2: Invert display rescaling on drag-to-override

**Files:**
- Modify: `app/javascript/controllers/library_vibe_map_controller.js`
- Create: `spec/system/vibe_map_rescale_spec.rb`

**Interfaces:**
- Consumes: `data-library-vibe-map-valence-min-value` / `-valence-max-value` / `-arousal-min-value` / `-arousal-max-value` (produced by Task 1).
- Produces: nothing new consumed by later tasks — this closes out the library map work.

- [ ] **Step 1: Write the failing system spec**

Create `spec/system/vibe_map_rescale_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Vibe Map rescaling", type: :system, js: true do
  let(:user) { create(:user) }
  let(:low_album) { create(:album, :grounded, title: "Low Album") }
  let(:high_album) { create(:album, :grounded, title: "High Album") }

  # Deliberately asymmetric ranges (not centered on 0.5): dragging to the
  # canvas's exact center (50% display) inverts to a value other than 0.5,
  # so this fixture actually distinguishes "inverted correctly" from
  # "screen fraction used directly, uninverted" — a symmetric 0.2/0.8 range
  # would invert 50% display back to 0.5 either way and prove nothing.
  before do
    create(:mood_vector, album: low_album, valence: 0.2, arousal: 0.3)
    create(:mood_vector, album: high_album, valence: 0.6, arousal: 0.5)
    CollectionItem.create!(user: user, album: low_album, release_id: 1)
    CollectionItem.create!(user: user, album: high_album, release_id: 2)
    sign_in_as(user)
  end

  it "stretches dot positions to the full display range" do
    visit vibe_map_path

    lefts = all("[data-album-id]").map { |marker| marker[:style][/left:\s*([\d.]+)%/, 1].to_f }
    expect(lefts.min).to eq(0.0)
    expect(lefts.max).to eq(100.0)
  end

  it "inverts a dragged position back into true valence/arousal before saving an override" do
    visit vibe_map_path

    find("[data-album-id='#{low_album.id}']").drag_to(find(".vibe-map-canvas"))

    expect(page).to have_css(".vibe-map-dot--saved")

    # Dragging to the canvas center is display fraction (0.5, 0.5). Correctly
    # inverted against this fixture's ranges: valence = 0.2 + 0.5*(0.6-0.2) = 0.4,
    # arousal = 0.3 + 0.5*(0.5-0.3) = 0.4. Uninverted (buggy) code would instead
    # save the raw screen fraction (0.5, 0.5) — 0.1 away, outside this tolerance.
    override = VibeOverride.find_by(user: user, album: low_album)
    expect(override.valence).to be_within(0.05).of(0.4)
    expect(override.arousal).to be_within(0.05).of(0.4)
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/system/vibe_map_rescale_spec.rb`
Expected: 1 of 2 examples FAILS. "stretches dot positions to the full display range" already PASSES (that's pure server-rendered display math, already implemented in Task 1). "inverts a dragged position back into true valence/arousal" FAILS — the current JS computes valence/arousal directly from screen fraction with no inversion, so dragging to the canvas center (50% display) saves raw `(0.5, 0.5)` instead of the correctly-inverted `(0.4, 0.4)`, which is 0.1 away — outside the test's `be_within(0.05)` tolerance.

- [ ] **Step 3: Implement the inverse transform in the Stimulus controller**

Replace `app/javascript/controllers/library_vibe_map_controller.js` with:

```javascript
import { Controller } from "@hotwired/stimulus"

const DRAG_THRESHOLD_PX = 4

export default class extends Controller {
  static targets = ["map"]
  static values = {
    valenceMin: Number,
    valenceMax: Number,
    arousalMin: Number,
    arousalMax: Number
  }

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
    this.dragging.valence = this.invert(x, this.valenceMinValue, this.valenceMaxValue)
    this.dragging.arousal = this.invert(1 - y, this.arousalMinValue, this.arousalMaxValue)
  }

  invert(displayFraction, min, max) {
    if (min === max) return displayFraction

    const value = min + displayFraction * (max - min)
    return Math.min(Math.max(value, 0), 1)
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

- [ ] **Step 4: Run the new spec to verify it passes**

Run: `bundle exec rspec spec/system/vibe_map_rescale_spec.rb`
Expected: 2 examples, 0 failures.

- [ ] **Step 5: Run the full existing vibe map system suite to confirm no regression**

Run: `bundle exec rspec spec/system/vibe_map_spec.rb spec/system/vibe_map_override_spec.rb spec/system/vibe_map_rescale_spec.rb`
Expected: 6 examples, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/library_vibe_map_controller.js spec/system/vibe_map_rescale_spec.rb
git commit -m "Invert Vibe Map display rescaling before saving drag overrides"
```

---

### Task 3: Album page header metadata (year, genres, styles)

**Files:**
- Modify: `app/helpers/application_helper.rb`
- Modify: `app/views/albums/show.html.erb`
- Create: `spec/requests/albums_spec.rb`

**Interfaces:**
- Consumes: `Album#year`, `Album#genres`, `Album#styles` (existing, no changes).
- Produces: `ApplicationHelper#pill(text)` — returns an HTML-safe `<span>` string. Task 5 reuses this exact helper for the vibe card's `time_of_day`/`seasons` badges.

- [ ] **Step 1: Write the failing request spec**

Create `spec/requests/albums_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "GET /albums/:id", type: :request do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  it "shows year, genres, and styles in the header" do
    album = create(:album, :grounded, title: "Kind of Blue", year: 1959, genres: [ "Jazz" ], styles: [ "Modal" ])

    get album_path(album)

    expect(response.body).to include("1959")
    expect(response.body).to include("Jazz")
    expect(response.body).to include("Modal")
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/requests/albums_spec.rb`
Expected: FAIL — `show.html.erb` currently only renders title and artists.

- [ ] **Step 3: Add the `pill` helper**

Replace `app/helpers/application_helper.rb` with:

```ruby
module ApplicationHelper
  def pill(text)
    content_tag(:span, text, class: "inline-block px-2 py-0.5 mr-1 mb-1 rounded-full bg-gray-100 text-gray-700 text-xs")
  end
end
```

- [ ] **Step 4: Add the header markup**

Replace `app/views/albums/show.html.erb` with:

```erb
<h1 class="text-2xl font-bold"><%= @album.title %></h1>
<p class="text-gray-600"><%= @album.artists.join(", ") %></p>

<div class="mt-2 mb-4">
  <% if @album.year.present? %>
    <span class="text-sm text-gray-500 mr-2"><%= @album.year %></span>
  <% end %>
  <% (@album.genres + @album.styles).each do |tag| %>
    <%= pill(tag) %>
  <% end %>
</div>

<%= render "albums/vibe_map", album: @album, mood: @vibe_mood %>
```

- [ ] **Step 5: Run the spec to verify it passes**

Run: `bundle exec rspec spec/requests/albums_spec.rb`
Expected: 1 example, 0 failures.

- [ ] **Step 6: Run the existing per-album system spec to confirm no regression**

Run: `bundle exec rspec spec/system/vibe_map_override_spec.rb`
Expected: 1 example, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add app/helpers/application_helper.rb app/views/albums/show.html.erb spec/requests/albums_spec.rb
git commit -m "Show year, genres, and styles on the album page"
```

---

### Task 4: Album page mood breakdown (all 6 dimensions)

**Files:**
- Modify: `app/views/albums/show.html.erb`
- Modify: `spec/requests/albums_spec.rb`

**Interfaces:**
- Consumes: `@vibe_mood` (existing controller ivar — a `MoodVector` or `VibeOverride::MoodSnapshot`, both respond to `MoodVector::MOOD_HEADS`), `MoodVector::MOOD_HEADS` (existing constant).
- Produces: nothing new consumed by later tasks.

- [ ] **Step 1: Write the failing request specs**

Add to `spec/requests/albums_spec.rb` (inside the existing `describe` block):

```ruby
  it "shows a mood breakdown for all six dimensions" do
    album = create(:album, :grounded)
    create(
      :mood_vector, album: album,
      valence: 0.62, arousal: 0.41, danceability: 0.73, mood_acoustic: 0.15, mood_relaxed: 0.28, mood_happy: 0.55
    )

    get album_path(album)

    expect(response.body).to include("0.62")
    expect(response.body).to include("0.41")
    expect(response.body).to include("0.73")
    expect(response.body).to include("0.15")
    expect(response.body).to include("0.28")
    expect(response.body).to include("0.55")
  end

  it "omits the mood breakdown when the album has no mood data" do
    album = create(:album)

    get album_path(album)

    expect(response.body).not_to include("Mood breakdown")
  end
```

- [ ] **Step 2: Run the new specs to verify they fail**

Run: `bundle exec rspec spec/requests/albums_spec.rb`
Expected: the 2 new examples FAIL (no mood breakdown markup exists yet); the earlier header example still PASSES.

- [ ] **Step 3: Implement the mood breakdown section**

Add this block to `app/views/albums/show.html.erb`, immediately after the `<%= render "albums/vibe_map", ... %>` line:

```erb

<% if @vibe_mood %>
  <div class="mt-6 max-w-md">
    <h2 class="text-lg font-semibold mb-2">Mood breakdown</h2>
    <% MoodVector::MOOD_HEADS.each do |head| %>
      <% value = @vibe_mood.public_send(head) %>
      <div class="mb-2">
        <div class="flex justify-between text-xs text-gray-500 mb-0.5">
          <span><%= head.to_s.humanize %></span>
          <span><%= value.round(2) %></span>
        </div>
        <div class="w-full h-1.5 bg-gray-100 rounded-full">
          <div class="h-1.5 bg-indigo-600 rounded-full" style="width: <%= (value * 100).round(1) %>%"></div>
        </div>
      </div>
    <% end %>
  </div>
<% end %>
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `bundle exec rspec spec/requests/albums_spec.rb`
Expected: 3 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/views/albums/show.html.erb spec/requests/albums_spec.rb
git commit -m "Show a 6-dimension mood breakdown on the album page"
```

---

### Task 5: Album page vibe card section

**Files:**
- Create: `spec/factories/vibe_cards.rb`
- Modify: `app/controllers/albums_controller.rb`
- Modify: `app/views/albums/show.html.erb`
- Modify: `spec/requests/albums_spec.rb`

**Interfaces:**
- Consumes: `Album#vibe_card` (existing `has_one`), `pill` helper (produced by Task 3).
- Produces: `@vibe_card` controller ivar (a `VibeCard` or `nil`) — not consumed by any later task in this plan.

- [ ] **Step 1: Create the vibe_card factory**

Create `spec/factories/vibe_cards.rb`:

```ruby
FactoryBot.define do
  factory :vibe_card do
    album
    time_of_day { [ "evening" ] }
    activities { [ "cooking dinner", "winding down" ] }
    energy_arc { "Starts mellow and builds gradually." }
    texture { "Warm analog synths over a steady groove." }
    seasons { [ "autumn" ] }
    prose { "A record built for slow evenings, leaning into warm, deliberate arrangements." }
  end
end
```

- [ ] **Step 2: Write the failing request specs**

Add to `spec/requests/albums_spec.rb`:

```ruby
  it "shows the vibe card when present with prose" do
    album = create(:album, :grounded)
    create(:vibe_card, album: album, prose: "A record built for slow evenings.")

    get album_path(album)

    expect(response.body).to include("A record built for slow evenings.")
  end

  it "omits the vibe card section when the vibe card has blank prose" do
    album = create(:album, :grounded)
    create(:vibe_card, album: album, prose: "")

    get album_path(album)

    expect(response.body).not_to include("Vibe card")
  end

  it "omits the vibe card section when no vibe card exists" do
    album = create(:album, :grounded)

    get album_path(album)

    expect(response.body).not_to include("Vibe card")
  end
```

- [ ] **Step 3: Run the new specs to verify they fail**

Run: `bundle exec rspec spec/requests/albums_spec.rb`
Expected: the "shows the vibe card" example FAILS (no vibe card markup exists); the two "omits" examples PASS vacuously (nothing to omit yet) — that's expected and fine, they'll stay meaningful once Step 5 adds the section.

- [ ] **Step 4: Add `@vibe_card` to the controller**

Replace `app/controllers/albums_controller.rb` with:

```ruby
class AlbumsController < ApplicationController
  def show
    @album = Album.find(params[:id])
    override = VibeOverride.find_by(user: Current.user, album: @album)
    @vibe_mood = override&.mood_snapshot || @album.mood_vector
    @vibe_card = @album.vibe_card
  end
end
```

- [ ] **Step 5: Implement the vibe card section**

Add this block to `app/views/albums/show.html.erb`, at the end of the file:

```erb

<% if @vibe_card&.prose.present? %>
  <div class="mt-6 max-w-md">
    <h2 class="text-lg font-semibold mb-2">Vibe card</h2>
    <div class="mb-2">
      <% @vibe_card.time_of_day.each do |t| %><%= pill(t) %><% end %>
      <% @vibe_card.seasons.each do |s| %><%= pill(s) %><% end %>
    </div>
    <p class="text-sm text-gray-700 mb-2"><strong>Activities:</strong> <%= @vibe_card.activities.join(", ") %></p>
    <p class="text-sm text-gray-700 mb-1"><%= @vibe_card.energy_arc %></p>
    <p class="text-sm text-gray-700 mb-2"><%= @vibe_card.texture %></p>
    <p class="text-sm text-gray-800"><%= @vibe_card.prose %></p>
  </div>
<% end %>
```

- [ ] **Step 6: Run the specs to verify they pass**

Run: `bundle exec rspec spec/requests/albums_spec.rb`
Expected: 6 examples, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add spec/factories/vibe_cards.rb app/controllers/albums_controller.rb app/views/albums/show.html.erb spec/requests/albums_spec.rb
git commit -m "Render the vibe card on the album page"
```

---

### Task 6: Per-album map numeric coordinates

**Files:**
- Modify: `app/views/albums/_vibe_map.html.erb`
- Modify: `spec/requests/albums_spec.rb`

**Interfaces:**
- Consumes: `mood` local (existing partial parameter, already passed as `@vibe_mood` from `show.html.erb`).
- Produces: nothing — final task in this plan.

- [ ] **Step 1: Write the failing request specs**

Add to `spec/requests/albums_spec.rb`:

```ruby
  it "shows the numeric valence/arousal coordinates on the per-album map" do
    album = create(:album, :grounded)
    create(:mood_vector, album: album, valence: 0.62, arousal: 0.41)

    get album_path(album)

    expect(response.body).to include("Valence 0.62")
    expect(response.body).to include("Arousal 0.41")
  end

  it "omits coordinates when the album has no mood data" do
    album = create(:album)

    get album_path(album)

    expect(response.body).not_to include("Valence")
  end
```

- [ ] **Step 2: Run the new specs to verify they fail**

Run: `bundle exec rspec spec/requests/albums_spec.rb`
Expected: the "shows the numeric coordinates" example FAILS; "omits coordinates" passes vacuously.

- [ ] **Step 3: Implement the coordinate display**

Replace `app/views/albums/_vibe_map.html.erb` with:

```erb
<div class="flex gap-2">
  <div class="flex flex-col justify-between text-xs font-medium text-gray-400 uppercase tracking-wide shrink-0 py-1">
    <span>Energetic</span>
    <span>Calm</span>
  </div>
  <div>
    <div
      data-controller="vibe-map"
      data-vibe-map-album-id-value="<%= album.id %>"
      data-vibe-map-genre-value="<%= album.genres.first %>"
      data-action="click->vibe-map#place"
      class="vibe-map"
      style="position: relative; width: 300px; height: 300px; border: 1px solid #ccc;"
    >
      <div
        class="vibe-map__marker"
        data-vibe-map-target="marker"
        style="position: absolute; transform: translate(-50%, -50%); width: 8px; height: 8px; border-radius: 9999px; background: #111;<% if mood %> left: <%= (mood.valence * 100).round(2) %>%; top: <%= ((1 - mood.arousal) * 100).round(2) %>%;<% end %>"
      ></div>
    </div>
    <div class="flex justify-between w-75 text-xs font-medium text-gray-400 uppercase tracking-wide mt-1">
      <span>Sad</span>
      <span>Happy</span>
    </div>
    <% if mood %>
      <p class="text-xs text-gray-500 mt-1">
        Valence <%= mood.valence.round(2) %> · Arousal <%= mood.arousal.round(2) %>
      </p>
    <% end %>
  </div>
</div>
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `bundle exec rspec spec/requests/albums_spec.rb`
Expected: 8 examples, 0 failures.

- [ ] **Step 5: Run the full related spec suite to confirm no regressions anywhere**

Run: `bundle exec rspec spec/requests/albums_spec.rb spec/requests/vibe_map_spec.rb spec/system/vibe_map_spec.rb spec/system/vibe_map_override_spec.rb spec/system/vibe_map_rescale_spec.rb`
Expected: 21 examples, 0 failures (8 + 7 + 3 + 1 + 2).

- [ ] **Step 6: Commit**

```bash
git add app/views/albums/_vibe_map.html.erb spec/requests/albums_spec.rb
git commit -m "Show numeric valence/arousal coordinates on the per-album map"
```
