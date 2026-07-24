# Vibe Map: zoom, density-aware labels, genre filter — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the library-wide Vibe Map's hand-rolled `<div>`-per-dot rendering with an Apache ECharts SVG chart, adding zoom/pan, density-aware label hiding, and a genre filter, per `docs/superpowers/specs/2026-07-23-vibe-map-zoom-density-genre-filter-design.md`.

**Architecture:** `VibeMapController#index` stops computing display percentages and instead serializes each album's raw mood values to JSON, embedded on the map container as a Stimulus `Array` value. `library_vibe_map_controller.js` initializes an ECharts chart (`renderer: "svg"`) with one `scatter` series per primary genre, `dataZoom` (type `"inside"`) for zoom/pan, `labelLayout: { hideOverlap: true }` for always-on-but-decluttered labels, and ECharts' built-in legend for the genre filter. Click-to-navigate and drag-to-override are implemented with ECharts' own `mousedown`/`click` events (which report whether the cursor hit a data point) plus `document`-level `mousemove`/`mouseup` listeners during an active drag, mirroring the existing threshold-based drag detection pattern — no manual affine-transform math, no custom collision-detection code.

**Tech Stack:** Rails 8.1, importmap-rails (no bundler), Hotwire/Stimulus, RSpec + Capybara (`type: :system, js: true` via `driven_by :selenium, using: :headless_chrome`), ECharts 6.1.0 (vendored `dist/echarts.esm.min.js`, SVG renderer).

## Global Constraints

- **Scope: `/vibe_map` only.** `app/views/albums/_vibe_map.html.erb` (the per-album single-dot map), its Stimulus controller `app/javascript/controllers/vibe_map_controller.js`, and `spec/system/vibe_map_override_spec.rb` (which tests that per-album map, via `visit album_path(album)` / `find(".vibe-map")`) are **not touched by this plan**. The design doc's own Testing section lists `vibe_map_override_spec.rb` among specs needing rewrite — that's a mistake in the design doc: that spec covers the out-of-scope per-album map, not the library-wide one. The library map's drag-to-override coverage actually lives inside `spec/system/vibe_map_spec.rb` (its third example). This plan corrects that.
- **ECharts renderer must be `"svg"`**, never the default canvas renderer — canvas output has no inspectable DOM per data point, which the system specs need.
- **ECharts `xAxis`/`yAxis` must always be present in `setOption` with at least `{ scale: true }`** — confirmed via a live spike (see Task 3): omitting `xAxis`/`yAxis` entirely throws (`Cannot read properties of undefined (reading 'get')` inside ECharts' cartesian2d init), and **without `scale: true`, ECharts' default numeric axis forces the range to include `0` with zero padding** (e.g. a single point at valence 0.7 gets axis extent `[0, 0.7]`, landing exactly on the right edge; a real multi-album axis would default to `[0, max(valence)]`, not `[min(valence), max(valence)]`) — this silently reintroduces the exact "wasted canvas, dots bunched together" problem this feature exists to fix. With `scale: true` confirmed via the same spike: two points at 0.2/0.8 auto-fit to extent exactly `[0.2, 0.8]` (matches the old manual rescale behavior), and a single point at (0.7, 0.3) auto-pads to a sane non-degenerate range (`[0.3, 1.1]` / `[0.1, 0.45]`) instead of a zero-width axis — replacing the old Ruby `rescale`/degenerate-axis-guard code entirely, safely.
- **No changes to `POST /albums/:id/vibe_override`** — same endpoint, same body params (`valence`, `arousal`, `danceability`, `mood_acoustic`, `mood_relaxed`, `mood_happy`, `genre`, `source`).
- **No cover art, no mobile/touch-specific gestures, no "select all/none" genre control** — out of scope per the design doc.
- Follow this repo's Ruby/Rails conventions (`~/.claude/CLAUDE.md` project instructions): domain logic in models, guard clauses, keyword shorthand, bang methods where failure should be explicit, no premature service-object extraction.

## Confirmed Capybara-targeting strategy (from spike)

Verified live against a real ECharts SVG scatter chart with `bundle exec rspec` (not guessed):

- **Production code never needs per-point DOM attributes.** ECharts' own `chart.on("mousedown", params => ...)` / `chart.on("click", params => ...)` deliver `params.componentType` (`"series"` if the cursor hit a rendered point, otherwise absent) and `params.data` (the exact data object for that point) — confirmed working correctly when the mouse event originates from a real Capybara `.click()`/Selenium action.
- **`renderItem`/declarative-shape `name` and `id` fields are NOT serialized to the SVG DOM** in ECharts 6.1.0's SVG renderer — confirmed empirically (dumped real rendered `<svg>` output; neither field appeared anywhere). Candidate #1 from the design doc, taken literally, does not work.
- **The working test-only targeting technique:** after any render, walk the SVG's `<path>` elements, and for each known `{albumId, valence, arousal}`, compute the expected pixel via `chart.convertToPixel({xAxisIndex:0, yAxisIndex:0}, [valence, arousal])`, then match against each candidate path's parsed center. ECharts draws a scatter point's circle symbol as two arcs whose `d` attribute starts at `(cx + r, cy)`, **not** `(cx, cy)` — confirmed via the regex below, which recovers the true center by subtracting the parsed radius:
  ```js
  const pattern = /^M(-?[\d.]+) (-?[\d.]+)A(-?[\d.]+) -?[\d.]+ 0 1 1 -?[\d.]+ -?[\d.]+$/
  // match[1], match[2] = arc start point; match[3] = radius r
  // true center: cx = match[1] - r, cy = match[2]
  ```
  With this correction, matching against the exact `chart.convertToPixel` output lands at `bestDist ≈ 0` for the correct point. Because real mood-vector coordinates are continuous floats, two distinct albums landing on the *exact* same pixel is not a realistic collision risk.
- **Selecting the matched element and driving Capybara's own `.click()` / `.drag_to()` on it works reliably** — confirmed, including surviving a legend-series toggle and a `dataZoom` zoom action without a `StaleElementReferenceError` (ECharts patches existing SVG nodes in place across those particular re-renders rather than tearing them down).
- **Do not use raw Selenium `action.click_and_hold.move_to_location(...).release.perform` chains for drag** — confirmed unreliable: a plain coordinate click works, but a multi-step drag built this way does not reliably fire the intermediate `mousemove` DOM events a `document`-level listener needs (verified: `window.__moveCount` stayed `undefined` across a 5-step chained move). Capybara's native `.drag_to()` (used above) does not have this problem and is what this plan uses throughout.
- **Dependency gotcha:** `./bin/importmap pin echarts` fails with a `404 Importmap::Packager::HTTPError` — echarts' package `index.js` entrypoint imports dozens of granular `zrender/lib/*` submodule specifiers that importmap-rails' downloader cannot resolve (it tries to pin `"zrender/lib/"` as a directory and 404s). The fix, used in Task 1: vendor the fully self-contained `dist/echarts.esm.min.js` build directly (verified zero external imports) and hand-add the `pin` line.

---

### Task 1: Add the ECharts dependency

**Files:**
- Modify: `config/importmap.rb`
- Create: `vendor/javascript/echarts.js`

**Interfaces:**
- Produces: an importmap pin named `"echarts"` that subsequent tasks import via `import * as echarts from "echarts"`.

- [ ] **Step 1: Download the self-contained ECharts dist bundle**

Run:
```bash
curl -sL --max-time 20 "https://cdn.jsdelivr.net/npm/echarts@6.1.0/dist/echarts.esm.min.js" -o vendor/javascript/echarts.js
```
Expected: the file exists and is non-empty.
```bash
wc -l vendor/javascript/echarts.js
```
Expected: a nonzero line count (the file is minified, so a handful of very long lines is normal — 45 as of echarts 6.1.0).

- [ ] **Step 2: Verify the vendored file has no external imports**

Run:
```bash
grep -o 'from"[a-zA-Z@][^"]*"' vendor/javascript/echarts.js | sort -u
grep -o "from'[a-zA-Z@][^']*'" vendor/javascript/echarts.js | sort -u
```
Expected: both commands print nothing (no output at all). This confirms the dist bundle is fully self-contained and safe to vendor as a single file — if either command prints something, stop and investigate before continuing (it means a newer/older echarts version reintroduced external imports and this vendoring approach needs revisiting).

- [ ] **Step 3: Add the importmap pin**

In `config/importmap.rb`, add this line after the `stimulus-loading` pin and before `pin_all_from "app/javascript/controllers", ...`:

```ruby
pin "echarts" # @6.1.0 (vendored dist/echarts.esm.min.js directly -- the package's ESM entrypoint
              # pulls in dozens of granular zrender/lib/* submodule specifiers that
              # `./bin/importmap pin echarts` cannot resolve; see plan Global Constraints)
```

The full file should read:

```ruby
# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "echarts" # @6.1.0 (vendored dist/echarts.esm.min.js directly -- the package's ESM entrypoint
              # pulls in dozens of granular zrender/lib/* submodule specifiers that
              # `./bin/importmap pin echarts` cannot resolve; see plan Global Constraints)
pin_all_from "app/javascript/controllers", under: "controllers"
```

- [ ] **Step 4: Verify nothing broke**

Run:
```bash
bundle exec rspec spec/system/vibe_map_spec.rb spec/system/vibe_map_override_spec.rb spec/requests/vibe_map_spec.rb
```
Expected: `11 examples, 0 failures` (adding an unused dependency pin must not change any existing behavior).

- [ ] **Step 5: Commit**

```bash
git add config/importmap.rb vendor/javascript/echarts.js
git commit -m "Add ECharts dependency, vendored as a self-contained dist bundle"
```

---

### Task 2: Simplify the controller to raw valence/arousal + JSON serialization

**Files:**
- Modify: `app/controllers/vibe_map_controller.rb:1-53`
- Modify: `spec/requests/vibe_map_spec.rb`

**Interfaces:**
- Produces: `@dots` (an `Array` of `VibeMapController::Dot`, now without `x_percent`/`y_percent`), and `@dots_json` (a JSON string of `{id, title, href, valence, arousal, genre, phrase, danceability, mood_acoustic, mood_relaxed, mood_happy}` per album) that Task 3's view embeds as a Stimulus value.
- Consumes: nothing new — same `Current.user.collection_items`, `Album.grounded`, `VibeOverride`, `MoodVectors::VibePhraseBuilder` as before.

- [ ] **Step 1: Write the failing request specs**

Replace the entire contents of `spec/requests/vibe_map_spec.rb` with:

```ruby
require "rails_helper"

RSpec.describe "GET /vibe_map", type: :request do
  let(:user) { create(:user) }

  before { sign_in_as(user) }

  def dots_from(response_body)
    html = Nokogiri::HTML5.parse(response_body)
    json = html.at_css("[data-library-vibe-map-dots-value]")["data-library-vibe-map-dots-value"]
    JSON.parse(json)
  end

  it "shows only the current user's grounded albums" do
    grounded = create(:album, :grounded)
    create(:mood_vector, album: grounded, valence: 0.7, arousal: 0.3)
    CollectionItem.create!(user: user, album: grounded, release_id: 1)

    get "/vibe_map"

    expect(response).to have_http_status(:ok)
    expect(dots_from(response.body).map { |d| d["id"] }).to include(grounded.id)
  end

  it "excludes another user's collection albums" do
    other_user = create(:user)
    other_album = create(:album, :grounded)
    create(:mood_vector, album: other_album)
    CollectionItem.create!(user: other_user, album: other_album, release_id: 2)

    get "/vibe_map"

    expect(dots_from(response.body).map { |d| d["id"] }).not_to include(other_album.id)
  end

  it "excludes ungrounded albums from the current user's own collection" do
    pending_album = create(:album)
    CollectionItem.create!(user: user, album: pending_album, release_id: 3)

    get "/vibe_map"

    expect(dots_from(response.body).map { |d| d["id"] }).not_to include(pending_album.id)
  end

  it "includes each dot's raw valence/arousal and mood fields, for the client to render and drag-override" do
    grounded = create(:album, :grounded, title: "Kind of Blue", genres: [ "Jazz" ])
    create(
      :mood_vector, album: grounded,
      valence: 0.7, arousal: 0.3, danceability: 0.2, mood_acoustic: 0.9, mood_relaxed: 0.1, mood_happy: 0.8
    )
    CollectionItem.create!(user: user, album: grounded, release_id: 15)

    get "/vibe_map"

    dot = dots_from(response.body).find { |d| d["id"] == grounded.id }
    expect(dot["title"]).to eq("Kind of Blue")
    expect(dot["href"]).to eq(Rails.application.routes.url_helpers.album_path(grounded))
    expect(dot["valence"]).to eq(0.7)
    expect(dot["arousal"]).to eq(0.3)
    expect(dot["genre"]).to eq("Jazz")
    expect(dot["danceability"]).to eq(0.2)
    expect(dot["mood_acoustic"]).to eq(0.9)
    expect(dot["mood_relaxed"]).to eq(0.1)
    expect(dot["mood_happy"]).to eq(0.8)
  end
end
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `bundle exec rspec spec/requests/vibe_map_spec.rb`
Expected: `FAIL` — the view has no element with a `data-library-vibe-map-dots-value` attribute yet, so `dots_from` raises `NoMethodError` on `nil` (`html.at_css(...)` returns `nil`).

- [ ] **Step 3: Rewrite the controller**

Replace the entire contents of `app/controllers/vibe_map_controller.rb` with:

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
    moods = albums.index_with { |album| overrides[album.id] || album.mood_vector }

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
        phrase: MoodVectors::VibePhraseBuilder.new(mood, genre: genre).call
      )
    end

    @dots_json = @dots.map do |dot|
      {
        id: dot.album.id,
        title: dot.album.title,
        href: album_path(dot.album),
        valence: dot.valence,
        arousal: dot.arousal,
        genre: dot.album.genres.first,
        phrase: dot.phrase,
        danceability: dot.danceability,
        mood_acoustic: dot.mood_acoustic,
        mood_relaxed: dot.mood_relaxed,
        mood_happy: dot.mood_happy
      }
    end.to_json
  end
end
```

- [ ] **Step 4: Temporarily add the JSON attribute to the view so the request specs can pass**

This task should not do the full view rewrite (that's Task 3), but the request specs need *something* to assert against. Modify `app/views/vibe_map/index.html.erb`: on the existing map container `<div>` (the one with `data-controller="library-vibe-map"`), add the new attribute alongside the existing ones, without removing anything yet:

```erb
data-library-vibe-map-dots-value="<%= @dots_json %>"
```

Leave the rest of the view (the per-dot `<div>` loop, the old `data-library-vibe-map-valence-min-value` etc.) untouched for now — Task 3 replaces all of it. This step exists purely so Task 2 is independently testable via the request specs without jumping ahead into Task 3's JS/view work.

- [ ] **Step 5: Run the request specs to verify they pass**

Run: `bundle exec rspec spec/requests/vibe_map_spec.rb`
Expected: `4 examples, 0 failures`

- [ ] **Step 6: Run the full existing suite to check for regressions**

Run: `bundle exec rspec spec/system/vibe_map_spec.rb spec/system/vibe_map_override_spec.rb`
Expected: `4 examples, 0 failures` — the system specs still exercise the old `x_percent`/`y_percent`-driven markup (untouched in this task), so they must still pass unchanged. If any fail, check that removing `x_percent`/`y_percent` from `Dot` didn't leave a dangling reference to those fields anywhere in the still-untouched view.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/vibe_map_controller.rb app/views/vibe_map/index.html.erb spec/requests/vibe_map_spec.rb
git commit -m "Simplify VibeMapController to raw valence/arousal + JSON dot serialization"
```

---

### Task 3: Replace the view and Stimulus controller with a base ECharts scatter chart

**Files:**
- Modify: `app/views/vibe_map/index.html.erb`
- Modify: `app/javascript/controllers/library_vibe_map_controller.js`
- Modify: `spec/system/vibe_map_spec.rb`
- Modify: `spec/system/vibe_map_rescale_spec.rb` (delete its first example only)
- Create: `spec/support/vibe_map_helpers.rb`

**Interfaces:**
- Consumes: `@dots_json` (Task 2), the confirmed `scale: true` axis requirement and the confirmed `path`-matching Capybara-targeting technique (Global Constraints / spike section above).
- Produces: `container.__echartsInstance` (the live ECharts instance, stashed on the map container DOM node purely for system-spec introspection — see step 3's comment), and the `find_vibe_map_point(album, valence:, arousal:)` spec helper that later tasks (4, 5, 6) reuse.

- [ ] **Step 1: Write the failing system spec**

Replace the entire contents of `spec/system/vibe_map_spec.rb` with:

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

  it "renders a point at the album's valence/arousal position and navigates to the album when clicked" do
    visit vibe_map_path

    point = find_vibe_map_point(album, valence: 0.7, arousal: 0.3)
    point.click

    expect(page).to have_current_path(album_path(album))
  end
end
```

- [ ] **Step 2: Add the spec helper (it doesn't exist yet, so this spec can't even boot without it)**

Create `spec/support/vibe_map_helpers.rb`:

```ruby
module VibeMapHelpers
  # ECharts' SVG renderer does not expose any custom identifying attribute on
  # rendered points (confirmed via a live spike: neither a `name` nor an `id`
  # field returned from a data item survives to the DOM). This walks the
  # rendered <path> elements and matches the one whose parsed center is
  # closest to the pixel position ECharts itself reports for the given
  # (valence, arousal), then stamps a `data-album-id` attribute onto it so
  # Capybara has something to select. Real mood-vector coordinates are
  # continuous floats, so two distinct albums landing on the exact same
  # pixel is not a realistic collision risk.
  STAMP_JS = <<~JS
    (function(albumId, valence, arousal) {
      var container = document.querySelector('[data-library-vibe-map-target="map"]')
      var chart = container.__echartsInstance
      var svg = container.querySelector('svg')
      var pattern = /^M(-?[\\d.]+) (-?[\\d.]+)A(-?[\\d.]+) -?[\\d.]+ 0 1 1 -?[\\d.]+ -?[\\d.]+$/
      var target = chart.convertToPixel({ xAxisIndex: 0, yAxisIndex: 0 }, [ valence, arousal ])
      var candidates = Array.from(svg.querySelectorAll('path')).filter(function(el) {
        return pattern.test(el.getAttribute('d') || '')
      })
      var best = null
      var bestDist = Infinity
      candidates.forEach(function(el) {
        var match = el.getAttribute('d').match(pattern)
        var r = parseFloat(match[3])
        var ex = parseFloat(match[1]) - r
        var ey = parseFloat(match[2])
        var dist = Math.hypot(ex - target[0], ey - target[1])
        if (dist < bestDist) { bestDist = dist; best = el }
      })
      if (best && bestDist < 2) best.setAttribute('data-album-id', String(albumId))
    })
  JS

  def find_vibe_map_point(album, valence:, arousal:)
    page.execute_script("(#{STAMP_JS})(arguments[0], arguments[1], arguments[2])", album.id, valence, arousal)
    find("[data-album-id='#{album.id}']")
  end
end

RSpec.configure do |config|
  config.include VibeMapHelpers, type: :system
end
```

- [ ] **Step 3: Run the spec to verify it fails**

Run: `bundle exec rspec spec/system/vibe_map_spec.rb`
Expected: `FAIL` — the view still renders the old `<div class="vibe-map-dot">` markup with no `<svg>` at all, so `find_vibe_map_point` raises (`container` is `null` or `container.__echartsInstance` is `undefined`).

- [ ] **Step 4: Rewrite the view**

Replace the entire contents of `app/views/vibe_map/index.html.erb` with:

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
      data-library-vibe-map-dots-value="<%= @dots_json %>"
      class="vibe-map-canvas relative w-full aspect-square border border-gray-300 rounded-lg bg-gray-50"
    ></div>
    <div class="flex justify-between text-xs font-medium text-gray-400 uppercase tracking-wide mt-1">
      <span>Sad</span>
      <span>Happy</span>
    </div>
  </div>
</div>
```

- [ ] **Step 5: Rewrite the Stimulus controller**

Replace the entire contents of `app/javascript/controllers/library_vibe_map_controller.js` with:

```js
import { Controller } from "@hotwired/stimulus"
import * as echarts from "echarts"

export default class extends Controller {
  static targets = ["map"]
  static values = { dots: Array }

  connect() {
    this.genres = [ ...new Set(this.dotsValue.map((dot) => dot.genre)) ]
    this.chart = echarts.init(this.mapTarget, null, { renderer: "svg" })
    this.chart.setOption(this.buildOption())

    // Stashed purely for system-spec introspection (see spec/support/vibe_map_helpers.rb) --
    // production code never reads this back.
    this.mapTarget.__echartsInstance = this.chart

    this.chart.on("click", (params) => this.onChartClick(params))
  }

  disconnect() {
    this.chart.dispose()
  }

  buildOption() {
    return {
      // `scale: true` is required: without it, ECharts' default numeric axis
      // forces the range to include 0 with no padding, which would bunch
      // real mood data into a corner -- exactly the problem this feature
      // exists to fix. With it, multiple points stretch to fill the full
      // range, and a single point still gets a sane, non-degenerate range
      // (confirmed via a live spike).
      xAxis: { scale: true, name: "Sad ↔ Happy", nameLocation: "middle", nameGap: 28 },
      yAxis: { scale: true, name: "Calm ↔ Energetic", nameLocation: "middle", nameGap: 32 },
      grid: { left: 48, right: 24, top: 24, bottom: 56 },
      legend: { data: this.genres, bottom: 8 },
      tooltip: {
        trigger: "item",
        formatter: (params) => params.data.dot.phrase
      },
      series: this.genres.map((genre) => ({
        name: genre,
        type: "scatter",
        symbolSize: 12,
        data: this.dotsValue
          .filter((dot) => dot.genre === genre)
          .map((dot) => ({ value: [ dot.valence, dot.arousal ], dot })),
        label: {
          show: true,
          position: "right",
          formatter: (params) => params.data.dot.title
        },
        labelLayout: { hideOverlap: true }
      }))
    }
  }

  onChartClick(params) {
    if (params.componentType !== "series") return

    Turbo.visit(params.data.dot.href)
  }
}
```

- [ ] **Step 6: Run the spec to verify it passes**

Run: `bundle exec rspec spec/system/vibe_map_spec.rb`
Expected: `1 example, 0 failures`

- [ ] **Step 7: Remove the now-obsolete rescale-display-range spec example**

`spec/system/vibe_map_rescale_spec.rb` has two examples. Its first (`"stretches dot positions to the full display range"`) asserts against the old `left:`/`style` percentage markup that no longer exists — delete only that example. Its second (`"inverts a dragged position back into true valence/arousal before saving an override"`) will be rewritten in Task 4, once drag-to-override exists in the new implementation — leave it as-is for now (it will fail if run, which is expected and addressed next task).

Edit `spec/system/vibe_map_rescale_spec.rb`, removing this block:

```ruby
  it "stretches dot positions to the full display range" do
    visit vibe_map_path

    lefts = all("[data-album-id]").map { |marker| marker[:style][/left:\s*([\d.]+)%/, 1].to_f }
    expect(lefts.min).to eq(0.0)
    expect(lefts.max).to eq(100.0)
  end

```

- [ ] **Step 8: Run the full existing suite**

Run: `bundle exec rspec spec/system/vibe_map_spec.rb spec/system/vibe_map_override_spec.rb spec/requests/vibe_map_spec.rb`
Expected: `spec/system/vibe_map_spec.rb` passes (1 example); `spec/system/vibe_map_override_spec.rb` (per-album map, untouched) passes (1 example); `spec/requests/vibe_map_spec.rb` passes (4 examples). `spec/system/vibe_map_rescale_spec.rb`'s remaining drag example is expected to fail until Task 4 — do not run that file yet.

- [ ] **Step 9: Manual verification of density-aware label hiding (documented, not automated)**

Per the design doc, label hide/show is a visual-layout behavior that Capybara cannot meaningfully assert (it can't tell "this label is hidden because it overlapped" apart from "this label doesn't exist"). This plan follows the design doc's own guidance to make that decision explicit rather than skip it silently: **this behavior is verified manually, not by an automated spec.**

Start the dev server and visually confirm in a real browser:
```bash
bin/rails server
```
Visit `/vibe_map` signed in as a user with many grounded albums clustered close together in mood space. Confirm: (a) labels visibly disappear where two or more would overlap, (b) zooming in (scroll/pinch) makes previously-hidden labels reappear as points spread apart on screen.

- [ ] **Step 10: Commit**

```bash
git add app/views/vibe_map/index.html.erb app/javascript/controllers/library_vibe_map_controller.js spec/system/vibe_map_spec.rb spec/system/vibe_map_rescale_spec.rb spec/support/vibe_map_helpers.rb
git commit -m "Rewrite Vibe Map rendering as an ECharts SVG scatter chart with per-genre series and density-aware labels"
```

---

### Task 4: Drag-to-override

**Files:**
- Modify: `app/javascript/controllers/library_vibe_map_controller.js`
- Modify: `spec/system/vibe_map_spec.rb`
- Modify: `spec/system/vibe_map_rescale_spec.rb`

**Interfaces:**
- Consumes: `this.chart` and `buildOption()`/`onChartClick` from Task 3.
- Produces: a `data-saved-album-id` attribute set on the map container after a successful override save, which specs assert against (there's no more single small `<div>` per dot to attach a `--saved` CSS class to, so the container itself carries this signal instead).

- [ ] **Step 1: Write the failing system spec**

Add this example to `spec/system/vibe_map_spec.rb`, inside the existing `RSpec.describe` block, after the click-to-navigate example:

```ruby

  it "posts an override with the new position and preserves other mood values on drag" do
    visit vibe_map_path

    point = find_vibe_map_point(album, valence: 0.7, arousal: 0.3)
    point.drag_to(find('[data-library-vibe-map-target="map"]'))

    expect(page).to have_css("[data-saved-album-id='#{album.id}']")
    expect(page).to have_current_path(vibe_map_path)

    override = VibeOverride.find_by(user: user, album: album)
    expect(override.source).to eq("vibe_map")
    expect(override.danceability).to eq(0.2)
    expect(override.mood_acoustic).to eq(0.9)
    expect(override.mood_relaxed).to eq(0.1)
    expect(override.mood_happy).to eq(0.8)
  end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/system/vibe_map_spec.rb`
Expected: `FAIL` on the new example — dragging currently does nothing (`onChartClick` only handles plain clicks; there's no mousedown/mousemove/mouseup wiring yet), so no `VibeOverride` is created and `[data-saved-album-id=...]` never appears.

- [ ] **Step 3: Add drag tracking to the Stimulus controller**

In `app/javascript/controllers/library_vibe_map_controller.js`, add a `DRAG_THRESHOLD_PX` constant above the class (matching the existing per-album controller's convention), and extend `connect()`/add new methods:

```js
import { Controller } from "@hotwired/stimulus"
import * as echarts from "echarts"

const DRAG_THRESHOLD_PX = 4

export default class extends Controller {
  static targets = ["map"]
  static values = { dots: Array }

  connect() {
    this.genres = [ ...new Set(this.dotsValue.map((dot) => dot.genre)) ]
    this.chart = echarts.init(this.mapTarget, null, { renderer: "svg" })
    this.chart.setOption(this.buildOption())

    this.mapTarget.__echartsInstance = this.chart

    this.chart.on("mousedown", (params) => this.onChartMouseDown(params))
    this.chart.on("click", (params) => this.onChartClick(params))
  }

  disconnect() {
    this.chart.dispose()
  }

  buildOption() {
    return {
      xAxis: { scale: true, name: "Sad ↔ Happy", nameLocation: "middle", nameGap: 28 },
      yAxis: { scale: true, name: "Calm ↔ Energetic", nameLocation: "middle", nameGap: 32 },
      grid: { left: 48, right: 24, top: 24, bottom: 56 },
      legend: { data: this.genres, bottom: 8 },
      tooltip: {
        trigger: "item",
        formatter: (params) => params.data.dot.phrase
      },
      series: this.genres.map((genre) => ({
        name: genre,
        type: "scatter",
        symbolSize: 12,
        data: this.dotsValue
          .filter((dot) => dot.genre === genre)
          .map((dot) => ({ value: [ dot.valence, dot.arousal ], dot })),
        label: {
          show: true,
          position: "right",
          formatter: (params) => params.data.dot.title
        },
        labelLayout: { hideOverlap: true }
      }))
    }
  }

  onChartMouseDown(params) {
    if (params.componentType !== "series") return

    this.dragging = {
      dot: params.data.dot,
      moved: false,
      startX: params.event.event.clientX,
      startY: params.event.event.clientY
    }
    this.boundMove = this.onDocumentMouseMove.bind(this)
    this.boundUp = this.onDocumentMouseUp.bind(this)
    document.addEventListener("mousemove", this.boundMove)
    document.addEventListener("mouseup", this.boundUp)
  }

  onDocumentMouseMove(event) {
    if (!this.dragging) return

    const dx = event.clientX - this.dragging.startX
    const dy = event.clientY - this.dragging.startY
    if (!this.dragging.moved && Math.hypot(dx, dy) > DRAG_THRESHOLD_PX) {
      this.dragging.moved = true
    }
  }

  onDocumentMouseUp(event) {
    document.removeEventListener("mousemove", this.boundMove)
    document.removeEventListener("mouseup", this.boundUp)

    const state = this.dragging
    this.dragging = null
    if (!state || !state.moved) return

    this.suppressNextClick = true

    const bounds = this.mapTarget.getBoundingClientRect()
    const px = event.clientX - bounds.left
    const py = event.clientY - bounds.top
    const [ valence, arousal ] = this.chart.convertFromPixel({ xAxisIndex: 0, yAxisIndex: 0 }, [ px, py ])

    this.saveOverride(state.dot, this.clamp01(valence), this.clamp01(arousal))
  }

  onChartClick(params) {
    if (this.suppressNextClick) {
      this.suppressNextClick = false
      return
    }
    if (params.componentType !== "series") return

    Turbo.visit(params.data.dot.href)
  }

  clamp01(value) {
    return Math.min(Math.max(value, 0), 1)
  }

  saveOverride(dot, valence, arousal) {
    const formData = new FormData()
    formData.append("valence", valence)
    formData.append("arousal", arousal)
    formData.append("danceability", dot.danceability)
    formData.append("mood_acoustic", dot.mood_acoustic)
    formData.append("mood_relaxed", dot.mood_relaxed)
    formData.append("mood_happy", dot.mood_happy)
    formData.append("genre", dot.genre || "")
    formData.append("source", "vibe_map")

    const headers = {}
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (csrfToken) headers["X-CSRF-Token"] = csrfToken

    fetch(`/albums/${dot.id}/vibe_override`, {
      method: "POST",
      headers,
      body: formData
    }).then((response) => {
      if (response.ok) this.mapTarget.setAttribute("data-saved-album-id", dot.id)
    })
  }
}
```

Note the `this.suppressNextClick` guard in `onChartClick`: a completed drag (mouseup after moving past the threshold) may or may not also trigger a native `click` event depending on browser drag-distance heuristics. This guard makes the outcome deterministic either way — if `click` doesn't fire after a drag, the flag is simply set and cleared without effect; if it does fire, it correctly prevents an unwanted navigation immediately after saving an override. The new spec's `expect(page).to have_current_path(vibe_map_path)` assertion (Step 1) exists specifically to catch a regression here.

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/system/vibe_map_spec.rb`
Expected: `2 examples, 0 failures`

- [ ] **Step 5: Rewrite the drag-inversion example in the rescale spec**

`spec/system/vibe_map_rescale_spec.rb` still has its second example, asserting drag-to-override correctly inverts a dragged screen position into true valence/arousal when the axis range doesn't start at 0 or end at 1. Replace the entire file with:

```ruby
require "rails_helper"

RSpec.describe "Vibe Map drag inversion", type: :system, js: true do
  let(:user) { create(:user) }
  let(:low_album) { create(:album, :grounded, title: "Low Album") }
  let(:high_album) { create(:album, :grounded, title: "High Album") }

  # Deliberately asymmetric ranges (not centered on 0.5): dragging to the
  # canvas's exact center inverts to a value other than 0.5 given these
  # ranges, so this fixture actually distinguishes "inverted via the current
  # zoomed/auto-fit axis extent" from "some other, wrong, transform" -- a
  # symmetric 0.2/0.8 range would invert center-drag back to 0.5 either way
  # and prove nothing.
  before do
    create(:mood_vector, album: low_album, valence: 0.2, arousal: 0.3)
    create(:mood_vector, album: high_album, valence: 0.6, arousal: 0.5)
    CollectionItem.create!(user: user, album: low_album, release_id: 1)
    CollectionItem.create!(user: user, album: high_album, release_id: 2)
    sign_in_as(user)
  end

  it "inverts a dragged position back into true valence/arousal via the chart's current axis extent" do
    visit vibe_map_path

    point = find_vibe_map_point(low_album, valence: 0.2, arousal: 0.3)
    point.drag_to(find('[data-library-vibe-map-target="map"]'))

    expect(page).to have_css("[data-saved-album-id='#{low_album.id}']")

    override = VibeOverride.find_by(user: user, album: low_album)
    expect(override.valence).to be_within(0.1).of(0.4)
    expect(override.arousal).to be_within(0.1).of(0.4)
  end
end
```

`drag_to` drops at the target element's center, i.e. the middle of the map container in screen pixels. With `scale: true` fitting the axis to this fixture's actual data (valence `[0.2, 0.6]`, arousal `[0.3, 0.5]`), the container's horizontal/vertical center corresponds to roughly `valence ≈ 0.4`, `arousal ≈ 0.4` — a wider tolerance (`0.1`) than the original spec used (`0.05`) is appropriate here because ECharts' exact `scale: true` padding (not just a bare min-max fit) shifts the true center slightly; the tolerance is chosen to still clearly distinguish "correctly inverted" from "raw screen fraction used uninverted" (which would produce `0.5`, `0.5` — outside this tolerance either way).

- [ ] **Step 6: Run the spec to verify it passes**

Run: `bundle exec rspec spec/system/vibe_map_rescale_spec.rb`
Expected: `1 example, 0 failures`

If the assertion is outside tolerance, don't widen the tolerance to make it pass — instead print the actual computed value (`puts override.valence, override.arousal`) and compare against `page.evaluate_script("document.querySelector('[data-library-vibe-map-target=\"map\"]').__echartsInstance.getModel().getComponent('xAxis').axis.scale.getExtent()")` to see the chart's actual resolved axis extent for this fixture's data, then adjust the expected value in the assertion (not the tolerance) to match the true center of that extent.

- [ ] **Step 7: Run the full suite**

Run: `bundle exec rspec spec/system/vibe_map_spec.rb spec/system/vibe_map_override_spec.rb spec/system/vibe_map_rescale_spec.rb spec/requests/vibe_map_spec.rb`
Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add app/javascript/controllers/library_vibe_map_controller.js spec/system/vibe_map_spec.rb spec/system/vibe_map_rescale_spec.rb
git commit -m "Add drag-to-override for the ECharts Vibe Map via chart.convertFromPixel"
```

---

### Task 5: Zoom & pan (dataZoom), with a drag-vs-pan conflict guard

**Files:**
- Modify: `app/javascript/controllers/library_vibe_map_controller.js`
- Modify: `spec/system/vibe_map_spec.rb`

**Interfaces:**
- Consumes: `buildOption()`, `onChartMouseDown`/`onDocumentMouseUp` from Task 4.
- Produces: no new public interface — this task adds `dataZoom` to the option and temporarily disables it for the duration of a point-drag, so dragging a point doesn't also pan the canvas underneath it.

- [ ] **Step 1: Write the failing system spec**

Add this example to `spec/system/vibe_map_spec.rb`, after the drag-to-override example:

```ruby

  it "still overrides (not pans) when dragging a point with zoom/pan enabled" do
    visit vibe_map_path

    point = find_vibe_map_point(album, valence: 0.7, arousal: 0.3)
    point.drag_to(find('[data-library-vibe-map-target="map"]'))

    expect(page).to have_css("[data-saved-album-id='#{album.id}']")
    expect(VibeOverride.find_by(user: user, album: album)).to be_present
  end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/system/vibe_map_spec.rb`
Expected: `FAIL` — `dataZoom` doesn't exist yet in `buildOption()`, so this test is currently identical to the existing drag-to-override test and should actually pass already at this point; that's fine and expected (it's not yet exercising anything new). Continue to the next step regardless — the meaningful assertion is that this **keeps passing once `dataZoom` is added**, which Step 4 verifies.

- [ ] **Step 3: Add `dataZoom` and a drag-vs-pan guard**

In `app/javascript/controllers/library_vibe_map_controller.js`:

Add `dataZoom` to `buildOption()`:

```js
  buildOption() {
    return {
      xAxis: { scale: true, name: "Sad ↔ Happy", nameLocation: "middle", nameGap: 28 },
      yAxis: { scale: true, name: "Calm ↔ Energetic", nameLocation: "middle", nameGap: 32 },
      grid: { left: 48, right: 24, top: 24, bottom: 56 },
      legend: { data: this.genres, bottom: 8 },
      dataZoom: [
        { type: "inside", xAxisIndex: 0 },
        { type: "inside", yAxisIndex: 0 }
      ],
      tooltip: {
        trigger: "item",
        formatter: (params) => params.data.dot.phrase
      },
      series: this.genres.map((genre) => ({
        name: genre,
        type: "scatter",
        symbolSize: 12,
        data: this.dotsValue
          .filter((dot) => dot.genre === genre)
          .map((dot) => ({ value: [ dot.valence, dot.arousal ], dot })),
        label: {
          show: true,
          position: "right",
          formatter: (params) => params.data.dot.title
        },
        labelLayout: { hideOverlap: true }
      }))
    }
  }
```

Update `onChartMouseDown` and `onDocumentMouseUp` to disable/re-enable `dataZoom` for the duration of a point-drag, so dataZoom's own drag-to-pan gesture can't fight with our point-drag override gesture over the same mousedown-on-a-point event:

```js
  onChartMouseDown(params) {
    if (params.componentType !== "series") return

    this.chart.setOption({
      dataZoom: [
        { type: "inside", xAxisIndex: 0, disabled: true },
        { type: "inside", yAxisIndex: 0, disabled: true }
      ]
    })

    this.dragging = {
      dot: params.data.dot,
      moved: false,
      startX: params.event.event.clientX,
      startY: params.event.event.clientY
    }
    this.boundMove = this.onDocumentMouseMove.bind(this)
    this.boundUp = this.onDocumentMouseUp.bind(this)
    document.addEventListener("mousemove", this.boundMove)
    document.addEventListener("mouseup", this.boundUp)
  }
```

```js
  onDocumentMouseUp(event) {
    document.removeEventListener("mousemove", this.boundMove)
    document.removeEventListener("mouseup", this.boundUp)

    this.chart.setOption({
      dataZoom: [
        { type: "inside", xAxisIndex: 0, disabled: false },
        { type: "inside", yAxisIndex: 0, disabled: false }
      ]
    })

    const state = this.dragging
    this.dragging = null
    if (!state || !state.moved) return

    this.suppressNextClick = true

    const bounds = this.mapTarget.getBoundingClientRect()
    const px = event.clientX - bounds.left
    const py = event.clientY - bounds.top
    const [ valence, arousal ] = this.chart.convertFromPixel({ xAxisIndex: 0, yAxisIndex: 0 }, [ px, py ])

    this.saveOverride(state.dot, this.clamp01(valence), this.clamp01(arousal))
  }
```

- [ ] **Step 4: Run the spec to verify it still passes with dataZoom enabled**

Run: `bundle exec rspec spec/system/vibe_map_spec.rb`
Expected: `3 examples, 0 failures`. If dragging a point now pans the canvas instead of saving an override (i.e. `VibeOverride.find_by(...)` is `nil`), the `disabled: true`/`false` toggle isn't taking effect before the drag's first `mousemove` — as a fallback, try calling `params.event.event.stopPropagation()` at the top of `onChartMouseDown` (guarded by the `componentType === "series"` check) in addition to the `disabled` toggle, and re-run.

- [ ] **Step 5: Write and run a pan-doesn't-create-an-override regression check**

Add this example to `spec/system/vibe_map_spec.rb`, after the previous one:

```ruby

  it "does not create an override when dragging on empty canvas (pan, not point-drag)" do
    visit vibe_map_path

    canvas = find('[data-library-vibe-map-target="map"]')
    canvas.drag_to(canvas) # drag from/to the same empty-canvas element -- not a data point

    expect(VibeOverride.find_by(user: user, album: album)).to be_nil
  end
```

Run: `bundle exec rspec spec/system/vibe_map_spec.rb`
Expected: `4 examples, 0 failures`

- [ ] **Step 6: Manual verification of scroll/pinch zoom (documented, not automated)**

`dataZoom` type `"inside"` also responds to mouse-wheel scroll and trackpad pinch, which Capybara/Selenium cannot simulate meaningfully. Start the dev server and manually confirm: scrolling with the cursor over the map zooms in/out centered on the cursor; dragging on empty canvas pans.

- [ ] **Step 7: Run the full suite**

Run: `bundle exec rspec spec/system/vibe_map_spec.rb spec/system/vibe_map_override_spec.rb spec/system/vibe_map_rescale_spec.rb spec/requests/vibe_map_spec.rb`
Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add app/javascript/controllers/library_vibe_map_controller.js spec/system/vibe_map_spec.rb
git commit -m "Add dataZoom (zoom/pan) with a drag-vs-pan guard for point overrides"
```

---

### Task 6: Genre filter (legend) and rescale-on-filter

**Files:**
- Modify: `spec/system/vibe_map_spec.rb`

**Interfaces:**
- Consumes: the per-genre `series` array already built in `buildOption()` (Task 3) and ECharts' built-in legend (already configured via `legend: { data: this.genres, bottom: 8 }`, Task 3) — no production code changes are needed in this task; the genre filter already works as a side effect of the per-genre series architecture. This task's job is entirely to add test coverage proving it.

- [ ] **Step 1: Write a failing spec for the legend listing distinct genres**

Add this example to `spec/system/vibe_map_spec.rb`, after the existing ones. This needs a second album with a different genre to have something to filter:

```ruby

  it "lists each distinct genre in the legend and hides that genre's points on click" do
    rock_album = create(:album, :grounded, title: "Rock Album", genres: [ "Rock" ])
    create(:mood_vector, album: rock_album, valence: 0.2, arousal: 0.8)
    CollectionItem.create!(user: user, album: rock_album, release_id: 2)

    visit vibe_map_path

    expect(page).to have_text("Jazz")
    expect(page).to have_text("Rock")

    # both points are present and clickable before filtering
    find_vibe_map_point(album, valence: 0.7, arousal: 0.3)
    find_vibe_map_point(rock_album, valence: 0.2, arousal: 0.8)

    find("text", text: "Rock").click # toggle the Rock series off via the legend

    expect(page).to have_no_css("[data-album-id='#{rock_album.id}']", wait: 2)
  end
```

- [ ] **Step 2: Run the spec to verify it fails or passes**

Run: `bundle exec rspec spec/system/vibe_map_spec.rb`
Expected: this should already pass — the legend and per-genre series were built in Task 3, so toggling a legend entry is native ECharts behavior. If it fails, check that `find("text", text: "Rock")` is matching the legend's label text and not something else on the page (the album title "Rock Album" also contains "Rock" as a substring — Capybara's `text:` match is substring-based by default, which could make this selector ambiguous and pick the wrong `<text>` element). If ambiguous, use `find_all("text", text: "Rock").last` (the legend renders after the series' own label text in the SVG's DOM order) or scope the selector more tightly, e.g. `all("text", text: "Rock").find { |el| el.text == "Rock" }` (exact match, since the legend label's text content is exactly `"Rock"` while the album title's rendered label is `"Rock Album"`).

- [ ] **Step 3: Write a failing spec for rescale-on-filter**

Add this example, verifying that hiding a genre causes the remaining points' axis extent (and therefore their on-screen pixel position) to change — proving the "narrowed view always uses the full canvas" behavior the design doc calls for:

```ruby

  it "rescales axes to the remaining points when a genre is filtered out via the legend" do
    rock_album = create(:album, :grounded, title: "Rock Album", genres: [ "Rock" ])
    create(:mood_vector, album: rock_album, valence: 0.2, arousal: 0.8)
    CollectionItem.create!(user: user, album: rock_album, release_id: 2)

    visit vibe_map_path

    pixel_before = page.evaluate_script(<<~JS)
      window.document.querySelector('[data-library-vibe-map-target="map"]')
        .__echartsInstance.convertToPixel({xAxisIndex: 0, yAxisIndex: 0}, [0.7, 0.3])
    JS

    all("text", text: "Rock").find { |el| el.text == "Rock" }.click

    pixel_after = page.evaluate_script(<<~JS)
      window.document.querySelector('[data-library-vibe-map-target="map"]')
        .__echartsInstance.convertToPixel({xAxisIndex: 0, yAxisIndex: 0}, [0.7, 0.3])
    JS

    expect(pixel_after).not_to eq(pixel_before)
  end
```

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/system/vibe_map_spec.rb`
Expected: `6 examples, 0 failures`. This should pass without any production code change, since `scale: true` (Task 3) auto-fits the axis to whatever data is currently visible, and ECharts recalculates that automatically when a legend toggle hides a series. If `pixel_after` unexpectedly equals `pixel_before`, it likely means the album's own genre ("Jazz") is what's visible and unaffected while "Rock" is the one hidden — but since only Jazz's album (valence 0.7, arousal 0.3) remains visible, the axis should still tighten around just that one point instead of both, changing the resolved extent and therefore the pixel. If they're still equal, add `sleep 0.3` before re-reading `pixel_after` to rule out a render-timing race, and if that doesn't fix it, print both axis extents (`.__echartsInstance.getModel().getComponent('xAxis').axis.scale.getExtent()`) before/after to see what's actually happening.

- [ ] **Step 5: Run the full suite one final time**

Run: `bundle exec rspec spec/system/vibe_map_spec.rb spec/system/vibe_map_override_spec.rb spec/system/vibe_map_rescale_spec.rb spec/requests/vibe_map_spec.rb`
Expected: all pass (`6 + 1 + 1 + 4 = 12` examples, `0` failures).

- [ ] **Step 6: Commit**

```bash
git add spec/system/vibe_map_spec.rb
git commit -m "Add test coverage for the genre legend filter and rescale-on-filter behavior"
```

---

## Self-Review

**Spec coverage:**
- Zoom/pan → Task 5.
- Density-aware label hiding (`labelLayout: { hideOverlap: true }`) → Task 3 (rendering), manually verified per Task 3 Step 9.
- Genre filter (legend) → Task 6 (already functional from Task 3's per-genre series; Task 6 adds coverage).
- Rescale on filter → Task 6.
- Controller simplification (drop `x_percent`/`y_percent`, drop rescale/degenerate-axis Ruby code) → Task 2.
- Drag-to-override preserved, disambiguated by mousedown target, via `chart.convertFromPixel` → Task 4 (basic) + Task 5 (dataZoom conflict guard).
- Plain click still navigates → Task 3 + Task 4's `suppressNextClick` guard.
- SVG renderer requirement → Task 1/3 (`renderer: "svg"` in `echarts.init`).
- Existing spec rewrites: `spec/system/vibe_map_spec.rb` → Tasks 3/4/5/6; `spec/requests/vibe_map_spec.rb` → Task 2; `spec/system/vibe_map_rescale_spec.rb` → Tasks 3 (delete stale example)/4 (rewrite drag-inversion example). `spec/system/vibe_map_override_spec.rb` correctly left untouched (see Global Constraints correction).
- New coverage explicitly required by the design doc ("zoom/pan doesn't break click/drag", "a hidden genre's points are excluded from interaction") → Task 5 Step 5, Task 6 Step 1.
- Label hide/show manual-verification decision, made explicit rather than skipped silently → Task 3 Step 9.

**Placeholder scan:** no "TBD"/"handle appropriately"/unshown code — every step has literal file contents or exact commands with expected output.

**Type consistency:** `Dot` struct fields (Task 2) match the JSON keys used by the JS `dot` object throughout Tasks 3–6 (`id`, `title`, `href`, `valence`, `arousal`, `genre`, `phrase`, `danceability`, `mood_acoustic`, `mood_relaxed`, `mood_happy`). `find_vibe_map_point(album, valence:, arousal:)` (Task 3) is called with the same keyword signature in Tasks 4, 5, and 6. `data-saved-album-id` (Task 4) is asserted identically in Tasks 4, 5, and 6's specs (n/a for 6, only in 4/5).

Plan complete and saved to `docs/superpowers/plans/2026-07-24-vibe-map-zoom-density-genre-filter.md`.
