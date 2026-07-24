# Library redesign + Vibe Map — design

## Context

The Library page currently renders the user's collection as a bare `<ul>` of plain text — unreadable at scale (322 albums in the seed dataset). Separately, the original product vision (per the user, inspired by [everynoise.com](https://everynoise.com/)) called for a "vibe viewing map by album": a way to browse the whole collection spatially by mood rather than as a list. Neither exists today.

A search of `.superpowers/sdd/task-*.md` (tasks 6-10, the only ones covering vibe-related work) confirms this library-wide map was never part of a prior implementation plan — those tasks cover the per-album click-to-set `VibeOverride` map (`app/views/albums/_vibe_map.html.erb` + `vibe_map_controller.js`) and Madmin. This design covers new ground: a library-wide map, plus a redesign of the plain-list Library page.

**Current data reality:** the dev database has 322 albums, all `enrichment_status: pending`. Zero `MoodVector` or `VibeCard` rows exist anywhere. `EnrichAlbumJob` is what populates both (`MoodGroundingService` → `MoodVector`; `VibeCardGenerator` → `VibeCard`) in a single run. This means the Vibe Map will show nothing until enrichment is actually run against the real collection — that's a separate operational step, out of scope for this design, which only builds the UI and the data model support once mood data exists.

## 1. Phrase generation

A new class, `MoodVectors::VibePhraseBuilder` (`app/models/mood_vectors/vibe_phrase_builder.rb`), builds a short 2-3 word "vibe phrase" purely from a `MoodVector`'s six essentia-derived floats (valence, arousal, danceability, mood_acoustic, mood_relaxed, mood_happy) plus an optional genre string. No LLM involved — deterministic, free, instant, and testable with plain float inputs.

Per this repo's convention (small SRP classes live in a subdirectory under `app/models/` named after the model they relate to, not as instance methods on the model itself), this class is separate from `MoodVector`. `MoodVector` exposes a thin delegating method:

```ruby
def vibe_phrase(genre: nil)
  MoodVectors::VibePhraseBuilder.new(self, genre: genre).call
end
```

**Algorithm:**
1. For each of the 6 mood heads, compute its distance from neutral (`0.5`).
2. Take the 2 heads with the largest distance from neutral (the album's most distinctive traits).
3. Map each selected head + its band (low: `< 0.4`, high: `> 0.6`; heads landing in `0.4..0.6` are excluded from selection as "not distinctive") to an adjective, e.g.:
   - valence: low → "somber", high → "sunny"
   - arousal: low → "hushed", high → "driving"
   - danceability: low → "static", high → "danceable"
   - mood_acoustic: low → "electric", high → "acoustic"
   - mood_relaxed: low → "tense", high → "mellow"
   - mood_happy: low → "brooding", high → "joyful"
4. Join the (up to 2) adjectives with the album's first genre, e.g. `"hushed acoustic — Jazz"`. If fewer than 2 heads are distinctive (everything clusters near neutral), fall back to whatever adjectives are available, or genre alone.

**Override precedence:** when rendering the Vibe Map for a signed-in user, if a `VibeOverride` exists for that user+album, its values (not the raw `MoodVector`) feed both the phrase and the plotted position — an override represents the user's own correction of their felt vibe.

## 2. Vibe Map page (new)

- Route: `get "vibe_map" => "vibe_map#index", as: :vibe_map` (mirrors the existing `library` route style in `config/routes.rb`).
- `VibeMapController#index` (new) loads `Current.user`'s collection albums where `enrichment_status: "grounded"`. Ungrounded albums are simply absent from the map (no mood coordinates yet); they still show up in the Library table.
- Each album is a small dot absolutely positioned at `(valence, 1 - arousal)` as a percentage inside a large square map area. The full phrase isn't permanently rendered as visible text for every dot — only on hover/focus — to avoid an unreadable pile of overlapping labels as the grounded-album count grows. This is a deliberate v1 simplification vs. true everynoise-style always-on text; a denser text-layout treatment is a future enhancement, not required now.
- **Click** (no pointer movement) → navigates to `album_path(album)`.
- **Drag** (movement past a small pixel threshold) → the dot follows the cursor live; on release, `POST /albums/:id/vibe_override` (existing endpoint, `source: "vibe_map"`) with `valence`/`arousal` recomputed from the new position, and `danceability`/`mood_acoustic`/`mood_relaxed`/`mood_happy` carried over from the album's *current* mood snapshot (override if present, else `MoodVector`) rather than hardcoded to `0.5`. This is a small deliberate improvement over the existing per-album map's Stimulus controller, which zeroes those four fields on every click.
- New Stimulus controller `app/javascript/controllers/library_vibe_map_controller.js` — the existing `vibe_map_controller.js` (single marker, single album) is untouched and keeps serving the per-album page.

## 3. Library page (redesign)

`app/views/library/index.html.erb` becomes a table: **Title** (linked to `album_path`), **Artists**, **Year**, **Genres** (small pill/chips), **Status** (colored badge for `enrichment_status`). Default sort: artist, then title. The existing "Connect Discogs" empty state is unchanged. `LibraryController#index` gains an `order` clause and an `includes` guard against N+1s when rendering genre/status per row (already `.includes(:album)`; no change needed there since album is already eager-loaded).

## 4. Nav

`app/views/shared/_sidebar.html.erb` gets a 4th item, **Vibe Map**, positioned between Library and Feedback.

## 5. Testing

- **Model spec** (`spec/models/mood_vectors/vibe_phrase_builder_spec.rb`): band boundaries on each axis (low/mid/high), 2-most-distinctive-dimensions selection, genre inclusion, fallback when nothing is distinctive.
- **Request spec** (`spec/requests/vibe_map_spec.rb`): only the current user's grounded albums appear; another user's collection items are excluded; ungrounded albums are excluded.
- **System spec** (`spec/system/vibe_map_spec.rb`, `js: true`): a dot renders at the expected screen position derived from known mood values; clicking a dot navigates to the album; dragging and releasing a dot posts an override with the new position and preserves the album's other four mood values.

## Out of scope

- Running `EnrichAlbumJob` against the real 322-album collection (operational step, not a UI concern).
- Always-on text-label rendering with collision avoidance (everynoise's actual visual style) — deferred; v1 uses hover-to-reveal.
- Changing the per-album `_vibe_map.html.erb` / `vibe_map_controller.js` behavior.
- Wiring `VibeOverride` into `CandidateRetrieval`'s recommendation scoring (already flagged as out of scope in `task-10-brief.md`'s self-review notes).
