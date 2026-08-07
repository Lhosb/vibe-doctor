# Vibe Doctor — Code & Coffee Presentation Guide

A walkthrough for presenting Vibe Doctor to the dev team: what to show, in what order, and how to explain the AI/vector machinery under the hood.

---

## 1. The pitch (30 seconds)

Vibe Doctor is a vinyl collection manager (synced from Discogs) that recommends what to play next based on **mood/vibe**, not just genre or metadata. Every album gets audio-analyzed and LLM-annotated so recommendations can be driven by *how it sounds and feels*, not just tags.

Three pillars to hit:
- **The UI** — Library, Vibe Map, Recommend.
- **The recommendation pipeline** — hybrid of pgvector similarity search + LLM rerank + reinforcement-style feedback.
- **The admin surface (Madmin)** — operational visibility into the AI pipeline, plus invite-based user onboarding.

---

## 2. UI tour (demo order)

Sidebar nav (`app/views/shared/_sidebar.html.erb`): **Library → Vibe Map → Recommend → Feedback → Discogs → API Access → Admin** (admin-only).

1. **Library** (`library#index`) — the synced Discogs collection. Straightforward `has_many` list, nothing AI-flavored — good calm starting point.
2. **Vibe Map** (`vibe_map#index`) — visual/spatial entry point into the mood data. Save this for right before the deep dive since it's the most visually compelling.
3. **Recommend** (`recommend#index`) — the marquee feature. Type a free-text vibe ("warm sunday jazz"), optionally a genre, and get one album back with a rationale.
4. **Feedback** (`feedback#index`) — where "good / bad / skip" outcomes on past recommendations get recorded, feeding the affinity/cooldown loop.
5. **Discogs / API Access** — plumbing (collection sync, personal API token for the Siri Shortcut integration). Mention briefly, don't dwell.

### Vibe Map demo details
- Scatter plot: **x = valence (sad→happy)**, **y = arousal (calm→energetic)**, colored by genre, rendered with **ECharts** (`app/javascript/controllers/library_vibe_map_controller.js`).
- Hover a dot → tooltip shows a generated "vibe phrase" (e.g. *"sunny driving — Jazz"*).
- Click a dot → navigates to the album.
- **Drag a dot** → this is a nice live-demo moment: dragging repositions a point and POSTs to `/albums/:id/vibe_override`, creating a `VibeOverride` — a per-user manual correction that overrides the computed mood vector on future maps/recommendations (`app/models/albums/vibe_map_builder.rb:66`). Good talking point: *"the AI's read on a record isn't gospel — you can correct it."*
- There's also a global admin view (`vibe_map#global`, all users' collections) linked from Madmin's nav.

### Recommend demo details
- Single Stimulus controller (`recommend_controller.js`) does a fetch POST to `/recommend`, renders the result inline with no page reload.
- Show the "Give feedback" link in the result — ties directly into the feedback loop (section 4 below).
- Good demo queries: something evocative ("late night rainy drive," "getting ready to go out") rather than a genre name — showcases that it's reasoning about mood, not just doing genre lookup.

---

## 3. Deep dive: how a recommendation is actually made

Walk through `Recommendations::Pipeline#call` (`app/models/recommendations/pipeline.rb`) top to bottom — it's a clean, linear read and doubles as your slide outline:

```
query_text
   │
   ▼
1. QueryUnderstandingCache.fetch      → LLM extracts mood + genre + keywords + embeds the query text
   ▼
2. CandidateRetrieval                 → pgvector nearest-neighbor search across 4 facets, blended into one score
   ▼
3. GenreAdmissionFilter               → optionally restrict/soften to a requested genre
   ▼
4. RankedCandidate.rank               → blend in personal affinity + artist cooldown
   ▼
5. RerankClient (LLM, top 8)          → LLM re-scores the shortlist with a rationale
   ▼
6. TemperatureSampler                 → weighted-random pick (not just argmax) from the reranked scores
   ▼
7. persist_event + record_cooldown!   → log everything for feedback loop
   ▼
one album + a natural-language explanation
```

**Step-by-step talking points:**

1. **Query understanding** (`QueryUnderstandingClient`, cached 24h in `QueryUnderstandingCache`): an LLM call (`gpt-4o-mini`, structured output) turns free text into the *same 6-dimensional mood schema* Essentia produces from audio (valence, arousal, danceability, mood_acoustic, mood_relaxed, mood_happy) — plus a genre guess and keywords. It also generates a text embedding of the raw query. This is the key trick: **user intent and audio features are projected into the same mood space**, so they're directly comparable. Cached by a SHA-256 digest of the normalized query text, so repeat queries skip the LLM round-trip.

2. **Candidate retrieval** (`CandidateRetrieval`): runs **4 separate pgvector cosine-distance searches** (via the `neighbor` gem, `has_neighbors`) against 4 embedding columns — `sonic`, `emotional`, `situational`, `era` — each a 1536-dim OpenAI embedding (`text-embedding-3-small`). Distances are blended with fixed weights (sonic 0.30, situational 0.25, emotional 0.15, era 0.10) plus a mood-vector Euclidean distance term (weight 0.20) computed directly from the structured mood floats — not an embedding at all. So the "blended score" is **part semantic-embedding similarity, part structured numeric distance**. Worth calling out as a deliberate hybrid, not a pure vector search.

3. **Genre admission filter**: if the user typed a genre, don't hard-filter to it — admit anything within a small margin (0.08) of the best-scoring candidate's distance even if it doesn't match the genre. Prevents the genre field from being a brittle exact-match filter.

4. **Ranking** (`RankedCandidate`): converts blended distance to a similarity score, adds `AlbumAffinity` (learned per-user preference, weight 0.35), subtracts an `ArtistCooldown` penalty (recently-recommended artists are suppressed for 14 days, linearly decaying). This is the personalization layer — pure vector similarity doesn't know your taste history or that you just got 3 albums by the same artist.

5. **LLM rerank** (`RerankClient`): takes only the **top 8** ranked candidates (cost control) and asks an LLM to re-order them against the literal query text, returning a score + a human-readable rationale per album. This is where the eventual "explanation" text comes from.

6. **Temperature-sampled pick** (`TemperatureSampler`): rather than always returning the #1 reranked album, it does a softmax-weighted random draw (temperature 0.7) over the top 8. Deliberate anti-repetition/serendipity choice — same query won't always return the same album.

7. **Persistence**: every candidate's blended score and rerank score is stored on `RecommendationEvent` (full audit trail — great for the Madmin demo), and an `ArtistCooldown` is recorded for every artist on the chosen album.

**One-sentence summary for the room:** *"It's not one model doing everything — it's a small pipeline: an LLM for understanding intent, pgvector for fast candidate search across multiple facets, application-level scoring for personalization, a second LLM pass to rerank a short list, and a sampling step so it doesn't always pick the same 'best' answer."*

### 3.5 The math, unpacked (slide-worthy)

This is the part worth slowing down for — it's not one big black-box similarity score, it's several small, explainable pieces stacked together.

**What's a vector/embedding?** A list of floats a neural net produces for a piece of text, engineered so "similar meaning" → "similar numbers." `text-embedding-3-small` turns any string into 1536 floats. No single number means anything alone — only the *relative position* of two vectors matters. Toy 2-D version to draw on a whiteboard:

```
"sad piano ballad"      → [0.9, 0.1]
"melancholy jazz"       → [0.8, 0.3]   ← points nearly the same direction as above
"energetic dance track" → [0.1, 0.9]   ← points almost perpendicular to both
```

**Cosine distance:** `similarity = (A·B) / (|A|×|B|)`, ranges -1..1 (1 = same direction/meaning). `distance = 1 - similarity`, so **0 = identical, ~1 = unrelated**. It ignores vector *length* — only direction (meaning) counts, which is exactly right for text embeddings since magnitude is a model artifact, not a meaningful quantity.

**pgvector + `neighbor` gem, precisely:** pgvector is a Postgres extension adding a native `vector` column type and SQL distance operators (`<->` Euclidean, `<=>` cosine, `<#>` inner product), computed *inside the database*. The `neighbor` gem wires ActiveRecord to it — `has_neighbors :sonic` on `Embedding` (`app/models/embedding.rb`) marks that column as a pgvector column; `Embedding.nearest_neighbors(:sonic, vector, distance: "cosine")` compiles to roughly:

```sql
SELECT embeddings.*, (sonic <=> '[0.013,-0.044,...]') AS neighbor_distance
FROM embeddings ORDER BY sonic <=> '[0.013,-0.044,...]' LIMIT 100
```

`neighbor_distance` is a real cosine distance computed by Postgres, attached back to each returned record. Worth flagging: **there's no HNSW/IVFFlat index on these columns yet** — this is an exact brute-force scan today, fine at current catalog size, an easy "here's what we'd add at 10x scale" line if someone asks about performance.

**The 4 embedding columns — what data, what shape:** one `embeddings` row per album, 4 separate `vector(1536)` columns, each from its own OpenAI call over different text (`AlbumEmbeddingService`):

| column | built from |
|---|---|
| `sonic` | genres + styles text |
| `emotional` | vibe card energy/texture + a phrase rendered from the actual mood-vector numbers |
| `situational` | vibe card's time-of-day/activities/seasons/prose |
| `era` | artist/title/year |

**The subtlety:** the query only gets **one** embedding (`QueryUnderstandingClient#embed` — one call, one vector). `CandidateRetrieval` runs **four separate SQL queries**, comparing that *same* query vector against each of the four album-side columns in turn. It's 1 query vector checked against 4 different textual "views" of each album — not 4 vectors on each side — which works because query text and album text are embedded by the same model into the same shared space.

**Mood-vector distance is different math entirely:** `MoodVector#distance_to` is plain **Euclidean distance** over 6 floats (valence, arousal, danceability, mood_acoustic, mood_relaxed, mood_happy), each 0–1: `sqrt(Σ (a-b)²)`. Computed in Ruby, not Postgres — no index needed since it's one pairwise comparison per already-short-listed candidate. `MoodVector::MAX_DISTANCE = sqrt(6) ≈ 2.449` (worst case: every dimension off by 1.0) normalizes it into the same ~0–1 range as the cosine distances so it can be blended in.

**The blend, worked with numbers:** weights are `sonic 0.30 + situational 0.25 + emotional 0.15 + era 0.10 + mood 0.20 = 1.00` — deliberately sums to 1, so `blended_score` is a weighted average of 5 "badness" numbers (0 = perfect match). Made-up example, two candidates:

| facet | weight | Album A | Album B |
|---|---|---|---|
| sonic | 0.30 | 0.20 | 0.10 |
| situational | 0.25 | 0.15 | 0.40 |
| emotional | 0.15 | 0.10 | 0.10 |
| era | 0.10 | 0.30 | 0.30 |
| mood | 0.20 | 0.05 | 0.35 |

Album A: `.30(.20)+.25(.15)+.15(.10)+.10(.30)+.20(.05) = 0.1525`. Album B: `.30(.10)+.25(.40)+.15(.10)+.10(.30)+.20(.35) = 0.245`. **A wins** — even though B had the better raw genre/style match (`sonic`), it loses on `situational` and `mood`, which are weighted heavily enough to flip the result. That's the entire purpose of the blend: no single facet dominates alone.

From there: `similarity = 1 / (1 + blended_score)` turns distance into a score (higher = better, asymptotes to 1 as distance→0). Then `final_score = similarity + 0.35 × affinity − cooldown_penalty` layers your personal history in before the top 8 ever reach the LLM reranker.

### 3.6 What the LLM (`gpt-4o-mini`) actually does — and doesn't

Easy thing to get wrong in the room: **there isn't one AI model doing everything.** Two different OpenAI models play two different, non-overlapping roles:

- **`text-embedding-3-small`** — an *embedding-only* model. No chat, no generation. Its only job across the whole app is "turn this string into 1536 floats." It powers all the vector math in section 3.5.
- **`gpt-4o-mini`** — a *chat/structured-output* model. It never sees a vector and never computes a distance. It does exactly three narrow, bounded jobs:

| # | Where | When it runs | Input | Output | Kind of task |
|---|---|---|---|---|---|
| 1 | `QueryUnderstandingClient` | Online, once per new query (cached 24h) | Raw query text, e.g. *"warm sunday jazz"* | 6 mood floats + genre guess + keywords, forced into a fixed JSON schema | **Extraction/classification** — not generation |
| 2 | `RerankClient` | Online, once per query, on only the **top 8** candidates | Query text + those 8 albums' title/artist/genre | A re-ordering + a short rationale per album | **Judging/ranking a short list** |
| 3 | `VibeCardGenerator` | Offline, once per album, during enrichment (`EnrichAlbumJob`) | Album genre/style/era metadata | Time-of-day, activities, energy-arc, texture, seasons, 4–6 sentences of prose | **Generation** (the only genuinely generative use) |

A few things worth saying out loud to the room:

- **The explanation text users see is job #2's output.** `RecommendationEvent#explanation` and the "Give feedback" result card are literally the rationale the reranker wrote for whichever album the temperature sampler happened to pick — not a separate summarization step.
- **Job #1 doesn't write anything a person reads** — its whole purpose is projecting your free-text intent into the same 6-number mood space Essentia produces from real audio, so plain arithmetic (Euclidean distance, section 3.5) can compare "what you asked for" against "what the record sounds like."
- **The LLM never sees your whole catalog.** By the time job #2 runs, pgvector + the blended-score math has already cut thousands of albums down to 8. The LLM is judging a short list, not searching a library.
- **Job #3 is the odd one out** — it's the only place the LLM is asked to *create* new text rather than extract/classify/rank existing information, and it happens once at enrichment time, completely decoupled from any live recommendation request.

**One-liner for the room:** *"The AI doesn't pick the album — the math does. The LLM's job is to translate your words into numbers, judge a shortlist the math already produced, and (once, offline, per album) write the copy that describes it."*

---

## 4. Deep dive: vectors, Essentia, and vibe cards (where the data comes from)

This answers "where do all these numbers come from" — walk it in the order enrichment actually happens, via `EnrichAlbumJob` (`app/jobs/enrich_album_job.rb`), which orchestrates the whole pipeline per album and drives an explicit state machine on `Album#enrichment_status` (`pending → matching_audio → extracting_features → grounded`, or `failed`).

### 4a. Audio grounding — `MoodGroundingService`
Goal: get real audio for a record that's just Discogs metadata, then run signal analysis on it.
- **Try iTunes previews first** (`ItunesPreviewMatcher` + `SearchTermBuilder`): searches the iTunes Search API with a "ladder" of search terms (artist+title, title alone, title variants for dual-language titles), downloads 30-second preview clips.
- **Fall back to YouTube** (`YoutubeClipMatcher`) if no iTunes match, gated by a confidence threshold and a feature flag (`ENABLE_YOUTUBE_GROUNDING`).
- **Fall back to LLM-only defaults** (all mood dimensions = 0.5, neutral) if neither source finds audio — this is the honest "we don't actually know" state, tagged `mood_source: "llm_only"`.
- Matched audio clips get analyzed by **`EssentiaFeatureExtractor`** — shells out to a Python script (`script/essentia_extract.py`) using the **Essentia** audio analysis library, returning the 6 mood dimensions per track.
- Multiple tracks per album get averaged (mean + population stddev per dimension) into one `MoodVector` — this is the *actual audio-grounded* mood signal, tagged `mood_source: "essentia_itunes"` or `"essentia_youtube"`.

**What Essentia is actually doing (walk `script/essentia_extract.py` for this):** Essentia is an open-source audio *signal-processing* library (Music Technology Group, Barcelona) — not an LLM, works on raw waveforms, not text. Three stages:

1. **Load audio** mono, 16kHz (`es.MonoLoader`) — just decoding the file.
2. **Embed it** (`TensorflowPredictMusiCNN`, model `msd-musicnn-1.pb`) — a small CNN trained on the Million Song Dataset that turns a few seconds of audio into a numeric fingerprint of its musical content. This is the *audio* equivalent of what OpenAI's text embedding does for words — same idea, a totally different network trained on spectrograms instead of text.
3. **Run 5 small pretrained heads on that fingerprint:**
   - 4 binary classifiers — `danceability`, `mood_acoustic`, `mood_relaxed`, `mood_happy` — each its own model file, each a softmax over "yes/no." The code takes the "yes" class probability as the 0–1 score (e.g. `mood_happy: 0.82` = "82% confidence this sounds happy," per a model trained on human-labeled songs).
   - 1 regression model (`emomusic-msd-musicnn-2.pb`) for `valence`/`arousal`, trained on the EmoMusic dataset where humans rated songs 1–9 on the standard psychology affect scale. Its raw output is 1–9, so the code rescales: `(value - 1) / 8` → 0..1, to match the other four heads.

Each album gets up to 4 clips analyzed this way (from iTunes previews or YouTube — see above), and the results are averaged into one `MoodVector`. `spread` (population stddev per dimension) is stored and visible in Madmin, but **nothing downstream in the recommendation pipeline reads it yet** — good "future work" callout if asked.

**Talking point:** `MoodVector::MOOD_HEADS` (`valence, arousal, danceability, mood_acoustic, mood_relaxed, mood_happy`) is the same schema whether it comes from Essentia analyzing real audio *or* an LLM guessing from a text query — that shared schema is exactly why `MoodVector#distance_to` (section 3.5) is a meaningful comparison at all: you're comparing "what a neural net heard in the actual song" against "what an LLM inferred you meant," on the same 6 axes.

### 4b. Vibe Cards — `VibeCardGenerator`
An LLM call (`gpt-4o-mini`, structured output via `OpenAI::BaseModel` schema) that writes a **listening-context card** grounded in genre/style/era: time of day, activities, energy arc, texture, seasons, and 4-6 sentences of prose ("great for cooking dinner, unwinding after work," etc.). This is presentation-layer content but it *also* feeds back into the embeddings (next section) — show a `VibeCard` in Madmin to make this concrete.

### 4c. Embeddings — `AlbumEmbeddingService`
Builds **4 separate text embeddings per album** (`text-embedding-3-small`, 1536-dim each), one per facet, each built from a different slice of the data:
- **sonic** — genres/styles text.
- **emotional** — vibe card energy/texture + a rendered mood descriptor (`MoodDescriptor`) built from the *actual* mood vector numbers, not the raw floats.
- **situational** — vibe card's time-of-day/activities/seasons/prose.
- **era** — artist/title/year.

**Talking point:** this is why retrieval isn't "one big embedding" — sonic similarity, emotional similarity, and situational similarity are deliberately separate vector spaces so they can be weighted independently in `CandidateRetrieval`.

Once mood vector + vibe card + embeddings all exist, the album flips to `enrichment_status: "grounded"` and becomes eligible for recommendations.

**Suggested flow for this section of the talk:** open a `grounded` album in Madmin, click through its `MoodVector` → `VibeCard` → `Embedding` records live, then point back at the pipeline diagram from section 3 and show how those three records map onto steps 1–2.

---

## 5. Feedback loop (ties 3 and 4 together)

- `POST /recommend/feedback` (`RecommendationsController#feedback`) records an outcome (`good`/`bad`/`skip`) on a `RecommendationEvent`.
- `RecommendationEvent#apply_outcome!` updates `AlbumAffinity` by a fixed reward (`good` +0.15, `bad` -0.20, `skip` -0.05), clamped to `[-1, 1]`.
- This affinity score is what step 4 of the pipeline (`RankedCandidate`) reads back to personalize future rankings.
- Combined with `ArtistCooldown` (set every time an album is actually recommended, regardless of feedback), the system self-adjusts: liked albums/artists surface more, disliked ones get suppressed, and everything gets a cooldown so you're not shown the same record every day.

**Good line:** *"This is a lightweight bandit-style feedback loop, not a trained model — the 'learning' is a couple of running scores per user, but it's enough to make the second week of recommendations noticeably better than the first."*

---

## 6. Madmin admin dashboard

Point out this is **Madmin** (auto-generated Rails admin), gated behind `Current.user&.admin?` in the sidebar. Good resources to click through live, in this order:

1. **Albums** — see `enrichment_status` per record; good place to explain the state machine (`Album::ENRICHMENT_TRANSITIONS`).
2. **Mood Vectors / Vibe Cards / Embeddings** — the concrete artifacts from section 4; this is the "receipts" moment for the AI explanation.
3. **Recommendation Events** — full audit trail per recommendation: `candidates_considered`, `blended_scores`, `rerank_scores`, `final_score`, `explanation`, `outcome`. This is the best single screen for "prove it's not a black box."
4. **Album Affinities / Artist Cooldowns** — the feedback-loop state per user.
5. **Query Understanding Caches** — shows the LLM's structured read of past queries, cached with a TTL.
6. **Invitations** — the invite feature (next section).
7. Custom admin nav item: **Global Vibe Map** (`config/initializers/madmin.rb`) — the all-users version of the vibe map, added via `Madmin.menu.before_render`.

### Invite feature walkthrough
There's no public signup — the app is invite-only:
- Admin creates an `Invitation` in Madmin with just an email (`InvitationResource`). Validations prevent inviting an email that already has an account or already has a pending invite (`app/models/invitation.rb`).
- The invitation's `show` page (via `InvitationResource`'s `member_action`s) exposes:
  - A **read-only signup link** (`edit_registration_url(token)`) — click-to-select for pasting into an email/Slack.
  - **Regenerate Link** — rotates the token and resets the 7-day expiration (`regenerate_link!`) without creating a new record.
  - **Revoke** — sets `revoked_at`, invalidating the link.
- The invitee visits `/registrations/:token/edit` → `RegistrationsController`. `set_invitation` guards on invalid/expired/revoked/already-accepted tokens with clear redirects. On successful signup, the user is created with the invitation's (locked-in) email, the invitation is marked `accepted_at`, and a session starts immediately (`start_new_session_for`).
- Rate-limited (10 attempts / 3 min) on the `update` action to blunt brute-forcing a token.

**Good demo:** create an invite live, copy the signup link, open it in an incognito tab, complete signup, then flip back to Madmin and show the invitation now shows status `accepted`.

---

## 7. Anticipated questions

- **"Is this using RAG?"** — Sort of, but it's retrieval feeding a *reranker*, not a generator. No chat/LLM-generated final text is stuffed with retrieved docs; the LLM only reranks and explains a shortlist that pgvector already narrowed down.
- **"Why 4 separate embeddings instead of one?"** — So the weighting in `CandidateRetrieval::FACET_WEIGHTS` can favor sonic similarity over situational similarity (or vice versa) without retraining anything — it's just adjustable arithmetic over 4 independent vector spaces.
- **"What happens if Essentia/iTunes/YouTube all fail?"** — Graceful degradation to neutral mood values (`mood_source: "llm_only"`), never a hard failure of the enrichment job for that reason alone (see `MoodGroundingService#default_attrs`).
- **"Is the recommendation deterministic?"** — No, intentionally: `TemperatureSampler` samples rather than argmaxes, so repeat queries can surface different (but all decent) picks.
- **"How does someone get an account?"** — Invite-only, admin-issued from Madmin; no public registration route exists.
