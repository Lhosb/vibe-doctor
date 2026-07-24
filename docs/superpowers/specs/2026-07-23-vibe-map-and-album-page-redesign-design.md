# Vibe Map & album page redesign — design

## Context

The library-wide Vibe Map (`app/views/vibe_map/index.html.erb`, shipped per [[2026-07-23-library-vibe-map-design]]) only conveys where a user's collection roughly congregates in mood space — beyond that it gives no useful information at a glance, since every dot is anonymous until hovered (native `title` tooltip showing a generated vibe phrase) or clicked (navigates to the album). Separately, the album detail page (`app/views/albums/show.html.erb`) is minimal to the point of being unhelpful: just a title, an artist line, and the per-album vibe map — it shows no genres/year/styles, and never renders the `VibeCard` data (time_of_day, activities, energy_arc, texture, seasons, prose) at all, despite that data existing once an album is grounded.

This design covers two related but independently shippable pieces of work:
1. Rescaling + always-on labels for the library-wide Vibe Map.
2. Expanding the album detail page with header metadata, a full 6-dimension mood breakdown, and a rendered vibe card — plus showing the per-album map's numeric coordinates.

Cover art is out of scope for both — there is currently no cover image field on `Album` and no pipeline fetching one from Discogs anywhere in the app. Introducing that is a separate, larger effort not part of this design.

## 1. Library Vibe Map: rescaling

**Problem:** dots are positioned directly from raw `valence`/`arousal` (0..1) as a percentage. Real mood data clusters in a sub-range (observed: roughly a diagonal band from low-valence/low-arousal to high-valence/high-arousal, occupying about a quarter of the square), so most of the canvas sits empty and points bunch together in the middle.

**Fix:** `VibeMapController#index` computes the min/max of valence and of arousal across the `@dots` being rendered, then linearly rescales each dot's position into the full 0..100% display range:

```ruby
scaled = (raw - min) / (max - min)
```

**Degenerate axis rule:** if an axis has no spread (`min == max` — e.g. a single grounded album, or a collection where every album still shares the same value), skip scaling for that axis and use the raw value as-is instead of centering at 50%. This is not just an edge-case guard — it's required to keep the existing `spec/system/vibe_map_spec.rb` passing, which asserts a single-album fixture (valence 0.7, arousal 0.3) lands at exactly `left: 70%, top: 70%`. Rescaling only makes sense when there's a real range to stretch against.

The `Dot` struct gains `x_percent`/`y_percent` (already-scaled), computed in the controller rather than the view, so the template stays a dumb renderer and the scaling math is unit-testable without a full system spec.

**Drag-to-override must invert the same transform.** Today, `library_vibe_map_controller.js` converts a mouse position directly into valence/arousal and POSTs it. Once positions are rescaled for display, a dragged screen position must be converted back into true valence/arousal before POSTing — otherwise every override saved via drag would silently store the wrong mood values. The controller needs the same min/max range the server used; pass it as Stimulus values on the map container (e.g. `data-library-vibe-map-valence-min-value`, `-valence-max-value`, `-arousal-min-value`, `-arousal-max-value`), and have `onMouseMove`/`onMouseUp` apply the inverse of the controller's linear transform (identity when min == max, matching the server's degenerate rule) before computing the POST body. Clamp the inverted result to `0..1` in case a drag lands outside the on-screen cluster bounds.

## 2. Library Vibe Map: always-on labels

Each dot's album title renders as an always-visible label (title only — no artist/genre in the on-map label; those stay available via the existing hover-tooltip vibe phrase), positioned immediately to the right of its dot and vertically centered on it — the point itself stays uncovered, the same convention as city labels on a map. Dot + label are wrapped in one absolutely-positioned container at the dot's `x_percent`/`y_percent`, so:
- both move together,
- the click-to-navigate and drag-to-reposition interactions cover the label too, not just the 12px dot (bigger, easier hit target),
- `.vibe-map-dot` stays the class on the inner circle specifically, so existing specs (`find(".vibe-map-dot").click`, `.drag_to(...)`) keep working unchanged.

Label text truncates via CSS (`max-width`, `overflow: hidden`, `text-overflow: ellipsis`, `white-space: nowrap`) rather than wrapping, so long titles can't distort the layout. No collision-avoidance layout algorithm — labels can overlap at high density. Per explicit product decision, if/when that becomes a real problem the next iteration is genre filtering (out of scope here, not this design).

## 3. Album detail page: header metadata

`AlbumsController#show` already computes `@vibe_mood` (override-aware valence/arousal/etc., same precedence as the library map: `VibeOverride` if present, else `MoodVector`). Add a header block under the title/artist line showing year, genres, and styles, reusing the same pill/chip styling the Library table (`app/views/library/index.html.erb`) already uses for genres — one consistent visual language instead of a one-off.

## 4. Album detail page: mood breakdown

A stat-bar section showing all 6 mood dimensions (`valence, arousal, danceability, mood_acoustic, mood_relaxed, mood_happy`), driven by the same `@vibe_mood` object the map marker uses, so the numbers and the marker can never drift out of sync. Each bar is a plain div (`style="width: #{(value * 100).round(1)}%"` on an `indigo-600` inner div over a light gray track — the same accent color already used for map dots) — matching the app's existing convention of zero JS charting dependencies (the dot-positioning code already uses the identical inline-percentage-width technique). Valence and arousal — the two also spatially plotted — additionally show their raw numeric value as text (the "actual coordinates" requirement), next to the existing visual marker, not replacing it.

If the album has no `mood_vector` and no override (not yet grounded), this section doesn't render.

## 5. Album detail page: vibe card

Renders `time_of_day` and `seasons` as pill badges (same visual language as genres/styles), `activities` as a short list, `energy_arc`/`texture` as short prose lines, and `prose` as the main descriptive paragraph.

**Guard condition:** `VibeCard` rows can legitimately exist fully blank — `EnrichAlbumJob` saves an empty one (schema defaults: `""`/`[]`, not null) when the LLM call fails. Render the section only when `vibe_card.present? && vibe_card.prose.present?`, so a failed-generation album doesn't show an empty, awkward-looking box instead of just omitting the section.

## Testing

- **Model/request spec** for the rescaling math: multi-album spread stretches correctly into 0..100%; single-value (degenerate) axis is identity, not a divide-by-zero.
- **New system spec** with 2+ albums at different mood values verifying drag-to-reposition still POSTs the correct true valence/arousal despite the visual rescale — the highest-risk spot for a bug, since it requires the client to correctly invert the server's transform.
- **Existing specs** (`spec/system/vibe_map_spec.rb`, `spec/system/vibe_map_override_spec.rb`, `spec/requests/vibe_map_spec.rb`) should pass unchanged given the degenerate-axis rule above.
- **System/request specs** for the album page: header renders year/genres/styles; mood breakdown renders all 6 dimensions with correctly rounded values; vibe card section renders when present with non-blank prose, and is absent when the vibe card is blank or missing entirely.

## Out of scope

- Cover art anywhere in the app (no data pipeline exists to fetch/store it from Discogs).
- Label collision avoidance / zoom-pan canvas for the library map (Approach B, not chosen) — if density becomes unreadable, the next step is genre filtering, not this design.
- Any new JS charting/visualization dependency (Approach C, not chosen) — mood breakdown bars stay plain Tailwind divs.
- Changing the vibe-phrase hover-tooltip behavior, or the underlying `VibePhraseBuilder` adjective vocabulary.
