# Vibe Map: zoom, density-aware labels, genre filter — design

## Context

[[2026-07-23-vibe-map-and-album-page-redesign-design]] added always-on title labels and display rescaling to the library-wide Vibe Map (`app/views/vibe_map/index.html.erb`), and explicitly deferred two things as "next iteration, only if density becomes unreadable": label collision avoidance / zoom-pan, and genre filtering. With the real library (322 grounded albums, 13 distinct genres), density has become unreadable — the diagonal mood band that most real music occupies produces a dense cluster of overlapping labels that makes the map unusable in that region (confirmed live via browser screenshot against the running dev server).

This design covers three related pieces of work for the library-wide Vibe Map only:
1. Zoom and pan.
2. Density-aware label hiding (labels hide when overlapping, reappear once zoom/pan gives them room).
3. Genre filtering.

**Scope note:** this applies only to `/vibe_map`. The per-album map on the album detail page (`app/views/albums/_vibe_map.html.erb`) shows a single dot — it has no density problem and is unchanged by this design.

## Approach: adopt Apache ECharts

The three requested features map almost directly onto built-in ECharts scatter-series capabilities: `dataZoom` (zoom/pan), `labelLayout: { hideOverlap: true }` (density-aware label hiding), and per-series `legend` toggling (genre filter). Hand-rolling all three in vanilla Stimulus/CSS — the convention used by the prior design — was considered and rejected: zoom/pan requires coordinate-transform math and drag-vs-pan gesture disambiguation from scratch, and label collision avoidance requires a decluttering algorithm with no existing precedent in the codebase. ECharts gets all three largely for free, at the cost of a new dependency and a rewrite of the map's rendering and interaction code.

D3 + d3-zoom (maximum control, but label decluttering would still need to be hand-written — no real savings over vanilla) and Plotly.js (excellent zoom/pan, but no automatic label-overlap avoidance for scatter text) were also considered and rejected in favor of ECharts, which is the only candidate covering all three features declaratively.

**Dependency mechanics:** this app uses `importmap-rails` (no bundler, no `package.json`). ECharts is added via `./bin/importmap pin echarts`, vendoring a single pinned ESM build — consistent with how `@hotwired/stimulus` etc. are already pinned. No build step is introduced.

**Renderer:** ECharts must use `renderer: 'svg'`, not the default canvas renderer. Canvas output is opaque to Capybara (no inspectable DOM per data point); SVG keeps every rendered point as a real DOM element, which the existing system-spec convention (`find(".vibe-map-dot").click`, `.drag_to(...)`) depends on being able to do.

## Controller: simplification, not growth

`VibeMapController#index` currently computes `x_percent`/`y_percent` via a manual min-max rescale with a degenerate-axis special case (`app/controllers/vibe_map_controller.rb`). ECharts auto-fits its axes to whatever data is currently visible, including the single-distinct-value case (it pads around a single value rather than dividing by zero), so this custom Ruby rescaling logic and its dedicated request specs (`spec/requests/vibe_map_spec.rb`'s three rescaling examples) are deleted entirely.

The controller's `Dot` struct drops `x_percent`/`y_percent` and instead exposes raw `valence`/`arousal` (ECharts will position points itself). The `index` action serializes `@dots` to JSON (album id, title, href, raw valence/arousal, phrase, primary genre, and the existing per-mood-dimension values needed for the override POST body: `danceability`, `mood_acoustic`, `mood_relaxed`, `mood_happy`) and passes it to the Stimulus controller as a JSON data attribute, replacing the current per-dot `<div>` markup.

## Zoom & pan

`dataZoom` (type: `"inside"`) on both axes: scroll wheel / pinch zooms centered on the cursor; dragging on empty canvas pans. No slider UI — kept minimal, consistent with the map's existing chrome-free design.

## Density-aware labels

Every point keeps its always-on album-title label (per the original design intent). `labelLayout: { hideOverlap: true }` hides labels that would visually collide and re-shows them once zoom/pan or a genre filter gives them room — no custom collision-detection code. Points whose labels are currently hidden still expose the vibe phrase via ECharts' tooltip on hover, replacing today's native `title` attribute tooltip with equivalent information.

## Genre filter

One ECharts series per album's **primary genre** (`album.genres.first` — consistent with how genre is already used for the drag-override POST body and the Library table). ECharts' built-in legend lists all distinct genres present in the current collection with their series color; clicking a legend entry toggles that genre's series visibility. No custom checkbox UI, no "select all/none" control — legend click behavior is ECharts' default.

**Rescale on filter:** when a genre is hidden via the legend, axes rescale to fit only the still-visible points (ECharts' default auto-fit behavior recalculates axis min/max from currently-visible series data) — a narrowed view always uses the full canvas rather than leaving a small subset clustered in one corner. This means points visibly move when the filter changes; that's accepted as the tradeoff for better canvas usage.

## Drag-to-override

Preserved, disambiguated by mousedown target: starting a drag on a data point still overrides that album's mood (same `POST /albums/:id/vibe_override` endpoint and body as today); starting a drag on empty canvas pans instead. The pixel→data-space inversion needed to compute the dragged valence/arousal uses ECharts' `chart.convertFromPixel(...)`, which already accounts for the current zoom/pan transform — this replaces the manual affine-transform inversion and the `data-library-vibe-map-valence-min-value`-style Stimulus values added by the prior design (both no longer needed once the controller stops rescaling).

A plain click (no drag) on a point still navigates to that album via `Turbo.visit`, same as today.

## Testing

**Flagged risk, needs a spike first:** exactly how Capybara reliably targets "the point representing album X" inside ECharts' SVG output (for `click`/`drag_to` in system specs) is not yet confirmed. The implementation plan should open with a small technical spike — render one ECharts custom scatter series with a couple of points via the SVG renderer and confirm a stable way to select an individual point (candidates: ECharts custom-series `renderItem` setting an identifying attribute on the rendered element, or coordinate-based `drag_to`/click using `chart.convertToPixel` to locate a known album's on-screen position) — before the rest of the plan is written in detail, since every drag/click system spec depends on the answer.

Existing specs that assert against the current `<div>`-based markup will not survive unchanged and must be rewritten:
- `spec/system/vibe_map_spec.rb` (dot rendering, click-to-navigate)
- `spec/system/vibe_map_override_spec.rb` (drag-to-override)
- `spec/system/vibe_map_rescale_spec.rb` (rescale + inverted drag — the rescale-specific assertions in this file no longer apply and should be removed; the drag-inversion coverage should be re-expressed against the new implementation)
- `spec/requests/vibe_map_spec.rb`'s three rescaling examples (removed; the remaining "shows only current user's grounded albums" / "excludes other user" / "excludes ungrounded" examples still apply, adjusted for the new JSON-serialization response shape)

New coverage needed: zoom/pan doesn't break click/drag; a hidden genre's points are excluded from what a system spec can interact with (or at least don't affect override/navigation of visible ones); label hide/show behavior is difficult to assert via Capybara (visual layout, not semantic DOM state) and may be better covered by manual/visual verification than an automated spec — the plan should decide this explicitly rather than skip it silently.

## Out of scope

- Cover art (unrelated, no data pipeline exists).
- Mobile/touch-specific gestures (pinch-to-zoom may work incidentally via ECharts defaults, but isn't a design requirement here).
- The per-album map (`albums/_vibe_map.html.erb`) — single dot, no density problem, unchanged.
- Changing the `/albums/:id/vibe_override` POST endpoint or its request body shape.
- A "select all / none" or search control for the genre legend — ECharts' default legend click behavior only.
