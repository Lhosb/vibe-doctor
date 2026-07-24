# Recommend page — design

## Context

The app already has a complete recommendation pipeline with no user-facing entry point:

- `RecommendationPipeline` (`app/models/recommendation_pipeline.rb`) orchestrates query understanding (`QueryUnderstandingClient`, LLM-backed free-text → mood vector + genre + keywords + embedding, cached via `QueryUnderstandingCache`), candidate retrieval (`CandidateRetrieval`, blends embedding similarity via the `neighbor`/pgvector gem with mood-vector distance), genre admission (`GenreAdmissionFilter`), ranking, reranking, and temperature sampling. It persists a `RecommendationEvent` (`outcome: pending`) and records `ArtistCooldown`.
- `RecommendationsController#create` exposes this at `POST /recommend`, already tested (`spec/requests/recommendations_spec.rb`): takes `query` (required) and `genre` (optional) params, returns `200` with `{ recommendation_event_id, album: { id, title, artists, genres }, explanation }`, `422` with `{ error }` when `RecommendationPipeline::NoCandidatesError` is raised (no admitted candidates), `400` with `{ error }` when `query` is missing.
- Separately, `FeedbackController` (`GET /feedback`, `POST /feedback`) shows the oldest pending `RecommendationEvent` for the current user (`RecommendationEvent.pending_for(current_user).first`, ordered by `created_at`) and lets them mark it good/bad/skip.

This design adds the missing piece: a page where a signed-in user types a vibe phrase (optionally a genre), gets back one recommended album, and can jump straight to giving feedback on that specific recommendation. **No changes to the recommendation pipeline, `RecommendationsController`, or the `POST /recommend` contract.**

## Architecture

**New route:** `get "/recommend", to: "recommend#index", as: :recommend`. The existing `post "/recommend", to: "recommendations#create"` has no `as:` alias today, so `recommend_path` is free to name the new `GET` route — both verbs can share the same URL without conflict.

**New controller** (`app/controllers/recommend_controller.rb`): single `index` action, no instance variables needed — the view is a static form, and results are rendered entirely client-side from the existing JSON endpoint's response. This mirrors `VibeMapController`'s "thin controller" shape but is even thinner since there's no server-side data to prepare.

**View** (`app/views/recommend/index.html.erb`): Tailwind-styled form (house style per `vibe_map/index.html.erb`) with:
- A text input for the vibe phrase (required).
- A text input for genre (optional).
- An empty result panel `<div>` that starts hidden/empty and is populated by Stimulus after a successful submit.

**Stimulus controller** (`app/javascript/controllers/recommend_controller.js`, new): on form submit (Enter or a submit button — both trigger the same handler), prevents default page navigation, builds a `FormData` with `query` and `genre` (if filled in), and does:

```js
fetch("/recommend", { method: "POST", headers, body: formData })
```

using the same CSRF-token-header pattern already used in `library_vibe_map_controller.js`'s `saveOverride`. On `200`, renders into the result panel: album title, artists (joined), explanation, a link to `album_path(album.id)`, and a link to `feedback_path(recommendation_event_id: recommendation_event_id)` (see below). On `400`/`422`, renders the server's `error` message as inline text instead. On a network-level failure (`fetch` rejecting), shows a generic retry message.

**Backend touch — additive only** (`app/controllers/feedback_controller.rb`):

```ruby
def index
  @event = pending_event_for(params[:recommendation_event_id])
end

private

def pending_event_for(id)
  return RecommendationEvent.pending_for(current_user).first if id.blank?

  current_user.recommendation_events.pending.find_by(id: id) ||
    RecommendationEvent.pending_for(current_user).first
end
```

If `recommendation_event_id` is present and resolves to one of the current user's still-pending events, show that one. Otherwise (param absent, wrong user's event, already-actioned event, bad id) fall back to today's exact behavior — oldest pending. The sidebar's existing plain `link_to feedback_path` is unaffected since it never sends the param.

**Sidebar** (`app/views/shared/_sidebar.html.erb`): add a "Recommend" `<li>` between Vibe Map and Feedback, same markup shape as the existing entries (icon + `link_to recommend_path`).

## Data flow

1. User types a vibe phrase (e.g. "warm sunday jazz"), optionally a genre, and submits.
2. `recommend_controller.js` POSTs `query` (+ `genre` if present) to `/recommend` — the existing, unchanged endpoint.
3. `RecommendationPipeline` runs; on success returns `{ recommendation_event_id, album: {...}, explanation }`.
4. The Stimulus controller renders the result panel with the album info and two links: to the album's own page, and to `feedback_path(recommendation_event_id: ...)`.
5. Clicking the feedback link loads `/feedback?recommendation_event_id=<id>`, which now shows that specific event's card (assuming it's still pending — it will be, since nothing else could have actioned it yet) instead of whatever the oldest pending event happens to be.

## Error handling

- **Missing/empty phrase:** the text input is `required`, so the browser blocks submission before any request is made; no server round-trip needed for this case.
- **`422` (`NoCandidatesError`)** — e.g. no grounded albums admitted for the query/genre combination: render the server's `error` message inline (e.g. "No matching albums found — try a different phrase or genre").
- **`400`** (defensive only, shouldn't trigger given the required client-side input) — same inline-error treatment, generic text.
- **Network/unexpected failure** (`fetch` throws, non-JSON response, etc.): generic "Something went wrong — try again" message. Worth calling out explicitly since this pipeline calls OpenAI twice (query understanding + rerank) and can genuinely fail transiently in ways most of this app's other endpoints don't.
- **Auth:** unauthenticated access to `GET /recommend` redirects to sign-in via the existing `ApplicationController` before-action — nothing new needed, same as every other page.
- **Double-submit while a request is in-flight:** the Stimulus controller disables the submit control for the duration of the fetch — a simple guard against firing a second LLM-backed request before the first returns.

## Testing

- **Request spec** for `GET /recommend`: renders the form (200, contains the phrase input).
- **Request spec** for the `FeedbackController#index` param addition:
  - With a `recommendation_event_id` for one of the current user's pending events, shows that event's card.
  - With another user's event id, falls back to oldest-pending (not an error — matches "invalid input falls back to default" behavior chosen above).
  - With a non-pending (already actioned) event id, falls back to oldest-pending.
  - With no param at all, existing behavior (oldest pending) is unchanged — the two pre-existing examples in `spec/requests/feedback_spec.rb` must keep passing untouched.
- **System spec** (`type: :system, js: true`) covering the full flow end to end: stub `RecommendationPipeline` the same way `spec/requests/recommendations_spec.rb` stubs the OpenAI client, visit `/recommend`, type a phrase, submit, see the result render with the expected album/explanation, click the feedback link, land on `/feedback` showing that same album's card.
- **System spec** for the error path: stub the pipeline to raise `NoCandidatesError`, submit, see the inline error message (no crash, no navigation).

## Out of scope

- Any change to `RecommendationPipeline`, `RecommendationsController`, or the `POST /recommend` request/response contract.
- A genre *picker* (dropdown/autocomplete over known genres) — the genre field is a plain optional text input passed straight through to the existing `genre` param, same as how genre is handled elsewhere in this app (e.g. the vibe map's drag-override body).
- Result history / showing more than one candidate — this page always shows exactly the single best match the pipeline returns today.
- Any change to how `RecommendationEvent` outcomes are recorded or scored (`AlbumAffinity`, `ArtistCooldown`) — untouched.
- Turbo Stream responses from `POST /recommend` — the existing JSON contract is reused as-is rather than adding a new response format to a stable, already-tested endpoint.
