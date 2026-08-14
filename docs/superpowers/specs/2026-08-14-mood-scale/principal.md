# MOOD-SCALE — Principal Engineer design review

**Author:** Keystone (Principal Engineer)
**Date:** 2026-08-14
**Repo:** /Users/lukeolson/projects/vibe-doctor
**Tree reviewed:** branch `docs/essentia-gem-v2-design` @ `1f8ad78`. The dispatch names base main
`cecb380`; `cecb380` is an ancestor of this branch but `main` currently points at `0499d9c`, so
`cecb380` is *not* main's tip. Nothing in the mood path differs between them — every file cited
below is unchanged since `cecb380` — but the dispatch's base statement is imprecise and I am
recording that rather than silently accepting it.
**Verdict on the directive as literally stated:** **object, with a counter-proposal.**
The directive is right about the *goal* and wrong about the *mechanism*. Details in §2.

---

## 0. Evidence

Everything below is re-derived from the code and the database, not from the dispatch.

Read: `app/models/mood_vector.rb`, `app/models/mood_vectors/essentia_mapper.rb`,
`app/models/mood_vectors/vibe_phrase_builder.rb`, `app/models/albums/vibe_map_builder.rb`,
`app/models/recommendations/candidate_retrieval.rb`, `app/models/vibe_override.rb`,
`app/models/query_understanding_cache.rb`, `app/services/mood_grounding_service.rb`,
`app/services/query_understanding_client.rb`, `app/services/mood_descriptor.rb`,
`app/services/album_embedding_service.rb`, `app/jobs/enrich_album_job.rb`,
`app/controllers/vibe_overrides_controller.rb`, `config/initializers/sonance_registry.rb`,
`db/schema.rb`, `app/javascript/controllers/library_vibe_map_controller.js`,
`app/views/albums/_vibe_map.html.erb`.

Read in the pinned gem (`sonance` v0.3.0, `cf8e613`, path
`~/.asdf/installs/ruby/4.0.1/lib/ruby/gems/4.0.0/bundler/gems/sonance-cf8e613e9a9b`):
`lib/sonance/registry.rb` (descriptor definitions), `lib/sonance/value.rb` (range enforcement).

Ran: `gh issue view 30`; four read-only `psql` queries against `vibe_doctor_development`
(spread, threshold-firing counts, pairwise correlations, row counts by source).

### 0.1 Baton's measurement reproduces exactly

My own query, n = 321 (`mood_source LIKE 'essentia%'`; 314 iTunes + 7 YouTube; 1 `llm_only` excluded):

| head | min | max | mean | stddev | variance | share of expected sq. distance |
|---|---|---|---|---|---|---|
| danceability | 0.00111 | 1.00000 | 0.5288 | 0.334815 | 0.112101 | **28.25 %** |
| mood_acoustic | 0.00000 | 0.99915 | 0.4234 | 0.320821 | 0.102926 | **25.94 %** |
| mood_relaxed | 0.00038 | 0.99995 | 0.5286 | 0.313610 | 0.098351 | **24.79 %** |
| mood_happy | 0.00413 | 0.99044 | 0.5453 | 0.268967 | 0.072343 | **18.23 %** |
| arousal | 0.27466 | 0.70789 | 0.4925 | 0.087005 | 0.007570 | **1.91 %** |
| valence | 0.34385 | 0.67390 | 0.5113 | 0.059234 | 0.003509 | **0.88 %** |

musicnn 97.21 %, emomusic 2.79 %. danceability : valence variance ratio = **31.9×**.
**Baton's numbers are correct.** The framing is correct too: for two points drawn from the same
head distribution, `E[(a−b)²] = 2·Var`, so an unweighted Euclidean metric apportions influence by
variance. For ranking against a *fixed* query point the constant part of a head's offset cancels
across albums, so the spread-driven share is the right measure of ranking influence — which makes
the emomusic pair very nearly ranking-inert today, not merely under-weighted.

### 0.2 Where I correct the dispatch and issue #30

**(a) The four musicnn clamps are dead; the two emomusic clamps are live.**
`registry.rb:258-273` defines the four musicnn heads with `range_kind: :hard`,
`sanity_range: (0.0..1.0)`. `value.rb:60-66,77` raises `MalformedOutputError` (a `TrackError`)
for anything outside the sanity range, and `mood_grounding_service.rb:116,129` rescues it and
skips the track. So `essentia_mapper.rb:24-27`'s four `clamp` calls are unreachable — issue #30
states this and it checks out.

`registry.rb:241-256` defines the emomusic pair with `range_kind: :nominal`,
`native_range: (1.0..9.0)` but `sanity_range: (-3.0..13.0)`. **The gem does not veto emomusic
values outside 1..9.** A raw value of 0.6 or 9.4 passes the gem and is then silently clamped by
`essentia_mapper.rb:44`. That path is live today, in the pinned gem, and leaves no trace.

Issue #30 is scoped to "the app's four softmax clamps". It does not mention the two emomusic
clamps, which are the only ones that can actually fire. **#30 is under-scoped.**

**(b) `EMOMUSIC_RANGE` is the *native* range, not the *enforced* range.**
`config/initializers/sonance_registry.rb:8-14` asserts the registry's `native_range` equals
`EssentiaMapper::EMOMUSIC_RANGE`. That assertion is fine as far as it goes, but nothing asserts
anything about `sanity_range`, which is the band the gem actually enforces and is 2× wider on
each side. The mapper divides by the *declared* band while the gem admits a much wider one —
that gap is the mechanism of the silent clamp in (a).

**(c) Dispatch constraint 4 is incomplete: `MoodDescriptor` is not display-only.**
`mood_descriptor.rb` uses the same 0.6/0.4 thresholds, and its output flows through
`album_embedding_service.rb:41-45` into the `emotional` facet embedding, which is 15 % of
`FACET_WEIGHTS` in `candidate_retrieval.rb:3`. It is a **recommendation input**, and it is
threshold-degenerate for exactly the compressed heads (§0.3). Any list of "display consumers that
keep 0..1" that includes `MoodDescriptor` is wrong.

**(d) Dispatch constraint 5 is right but narrower than stated.** Only the two emomusic heads are
affine-transformed; the four musicnn heads are stored *raw already* (`clamp` is a no-op on a value
the gem has already vetoed outside 0..1). So for 4 of 6 heads there is nothing more accurate to
recover, and for the other 2 the inversion `raw = v·8 + 1` is exact whenever no track was clamped.
"There is literally nothing more accurate available" is true only of emomusic, and only for
clamped rows.

### 0.3 Two findings the dispatch did not anticipate

**Finding A — the compression degrades the *display* too, so "0..1 is fine for display" is not
quite true.** `VibePhraseBuilder` calls a head distinctive when `|v − 0.5| > 0.1`
(`vibe_phrase_builder.rb:13,29,35`). Measured over the same 321 rows:

| head | rows passing DISTINCTIVE_THRESHOLD |
|---|---|
| valence | 32 / 321 (10 %) |
| arousal | 96 / 321 (30 %) |

The two most human-legible adjectives in `ADJECTIVES` — somber/sunny, hushed/driving — are
effectively disabled for 90 % and 70 % of the catalogue respectively. Same cause.

`MoodDescriptor` fires its phrases on: valence 32/321 (10 %), arousal 96/321 (30 %),
danceability 146 (45 %), acoustic 99 (31 %), relaxed 140 (44 %), happy 149 (46 %). The emotional
facet text is valence-blind for nine albums in ten.

**Finding B — the six heads are not six dimensions, and this bites *any* standardization.**
Measured Pearson correlations over the 321 grounded rows:

| pair | r |
|---|---|
| arousal ↔ mood_relaxed | **−0.901** |
| mood_relaxed ↔ mood_happy | −0.734 |
| valence ↔ arousal | +0.715 |
| mood_acoustic ↔ danceability | −0.697 |
| valence ↔ mood_happy | +0.681 |
| arousal ↔ danceability | +0.561 |

`arousal` and `mood_relaxed` share 81 % of their variance — they are one axis with a sign flip.
`MAX_DISTANCE = sqrt(6)` (`mood_vector.rb:4`) already assumes six orthogonal unit axes, which is
false. Today this is masked: arousal carries 1.9 % of influence, so the shared axis is expressed
once, through `mood_relaxed`. **Equalize the heads and you start double-counting it.** Any design
that raises emomusic to parity must say what it does about this, or it will trade one unchosen
weighting for another.

---

## 1. The defect, stated precisely

The recommendation metric apportions influence by *stored coordinate variance*. Nobody chose that
apportionment; it is an artifact of `rescale_emomusic` dividing by a declared band roughly 2.4×
wider than the realized one, against musicnn heads that arrive already spanning 0..1.

Note what the defect is **not**: it is not a loss of precision. All six stored floats are exact to
`round(10)` (`mood_grounding_service.rb:181`). The emomusic transform `(v−1)/8` is affine and
invertible; it destroys no information except at the clamp. **The recommendation defect lives
entirely in the metric, not in the storage.**

---

## 2. Why the owner directive, taken literally, makes recommendations worse

The directive says the recommendation path must use "the most accurate numbers", with 0..1
reserved for display. The natural implementation — persist raw descriptors, feed raw into
`distance_to` — is measurably worse than what we have.

Raw emomusic is `v·8 + 1`, so raw σ = 8× the stored σ. Re-running the variance shares in raw
space, musicnn unchanged:

| head | raw σ | raw variance | share |
|---|---|---|---|
| arousal | 0.6960 | 0.4845 | **44.3 %** |
| valence | 0.4739 | 0.2246 | **20.5 %** |
| danceability | 0.3348 | 0.1121 | 10.2 % |
| mood_acoustic | 0.3208 | 0.1029 | 9.4 % |
| mood_relaxed | 0.3136 | 0.0984 | 9.0 % |
| mood_happy | 0.2690 | 0.0723 | 6.6 % |

Storing raw and keeping unweighted Euclidean flips the imbalance from **97/3 musicnn** to
**65/35 emomusic**, with arousal alone at 44 % — and arousal is the head that duplicates
mood_relaxed at r = −0.901. That is not more accurate. It is a *different* arbitrary weighting,
arrived at by a different accident of units.

**Raw units are not a neutral space.** A Euclidean metric has no unit-free reading; whichever
space you store, the metric silently weights by that space's scale. There is no "most accurate
numbers" answer to a metric question — only an explicitly chosen one.

I therefore restate the directive in the form I believe the owner actually intends, and design to
this:

> **Recommendations must be computed in a space whose per-head influence is a deliberate,
> reviewable, and reproducible choice — never an artifact of an upstream model's output units.
> The 0..1 column stays as the display and interchange representation.**

Under that restatement, the owner is right and the fix is real. Under the literal reading, the fix
is a regression, and I have the number above to prove it. **This is the one thing in this document
I would ask the owner to sign off on before any code moves.**

---

## 3. Proposed design — two spaces, one stored

### 3.1 Space definitions

**Display space (`D`)** — unchanged. The six `float` columns on `mood_vectors`, each in 0..1,
validated at `mood_vector.rb:9`. Produced by `MoodVectors::EssentiaMapper#call`. Consumed by the
vibe map, the phrase builder, `VibeOverride`, madmin, and the album detail view. **No change.**

**Recommendation space (`R`)** — new, **derived, never stored**. Per-head standardization against
frozen catalogue statistics:

```
z_h(v) = (v − μ_h) / σ_h
```

`R` is computed on the fly at scoring time from the same `D` columns. It adds **zero** columns and
**zero** migration.

### 3.2 Where the statistics live — and why frozen, not live

`μ_h`, `σ_h` live in a new frozen constant, `MoodVectors::CatalogueScale`, carrying a
`VERSION` string and the n it was measured over.

**They must not be recomputed from the live catalogue.** If they are, adding one album silently
changes every user's recommendations, the same query returns different results across days with no
commit, and no spec can pin the behaviour. Frozen constants make the weighting a reviewed artifact
— which is the entire complaint about the status quo.

Guard against silent drift with a spec that recomputes σ over the current grounded rows and fails
if any head has drifted beyond a stated band (I would use ±25 % relative on σ). That converts
"our constants went stale" from an invisible slow rot into a red build with a named head.

### 3.3 The LLM bridge — dispatch constraint 2

`query_understanding_client.rb:9` asks the model for floats 0..1 "matching the same audio-mood
dimensions Essentia extracts". **The model cannot do this and does not do this.** Proof from the
data: no album in the catalogue has `arousal > 0.708` or `valence > 0.674`. An LLM emitting
`arousal: 0.9` for "high energy" names a point outside the entire realized range of the
catalogue. The two sides are not in the same space today; the code only asserts that they are.

The bridge: **read the LLM's 0..1 as a target percentile of the catalogue, not as a model score.**

```
z_q(q) = Φ⁻¹(clamp(q, 0.02, 0.98))
```

- `q = 0.5 → z = 0` — neutral means "typical for this catalogue", which is what
  `MoodGroundingService#default_attrs` (`:47`) already means by 0.5. Consistent.
- `q = 0.9 → z ≈ +1.28` — the top ~10 % of the catalogue on that head. That *is* what a listener
  means by "sunny".
- Monotone, unit-free, and requires the LLM to know nothing about emomusic scales.

`Φ⁻¹` is ~15 lines (Acklam or Moro rational approximation); no gem needed. The 0.02/0.98 clamp
keeps the tails finite.

Two consequences worth stating plainly:
1. **`QueryUnderstandingCache` stays valid across a scale-version bump.** It stores the LLM's raw
   0..1 (`query_understanding_cache.rb:15-20`); the bridge is applied at scoring time. Re-tuning
   `CatalogueScale` does not invalidate the cache. That is a deliberate placement, not luck.
2. `query_understanding_client.rb:7-13` should be reworded so the prompt asks for what we now
   read: *relative intensity, 0 = least in a typical collection, 1 = most*. Cheap, and it stops
   the prompt asserting something false.

### 3.4 Why this normalization, over the alternatives

| option | verdict |
|---|---|
| **z-score standardization (per-head), frozen** | **Chosen.** Uses all n rows, not two order statistics. Stable under catalogue growth. Reviewable as a table of six numbers. Makes the weighting explicit. No migration. |
| explicit per-head weights in `distance_to` | *Mathematically the same thing* (`w_h = σ_ref²/σ_h²`) and I would accept it as the implementation. But weights alone leave the query side un-recentred, so an LLM `arousal: 0.9` still lands outside the catalogue and burns weight budget on a near-constant offset. Weights + the §3.3 bridge = z-scoring. Pick the framing that reads better; I prefer z-score because the constant is `(μ, σ)` per head, which is directly checkable against the DB. |
| empirical per-head min–max | **Reject.** min/max are the two most extreme rows in the catalogue; one outlier moves the whole scale, and they only ever widen as the catalogue grows. Also only gets emomusic to 15.7 % combined (I computed it) — better than 2.8 %, still 3.5× under parity, for no gain in stability. |
| store raw + project the LLM vector | **Reject as the primary fix** — §2. Raw storage has independent merit (§4) but it does not fix the metric, and shipped alone it regresses it. |
| Mahalanobis / whitening | **Reject, deliberately.** It is the statistically correct answer to Finding B, but it makes the metric opaque, needs a stored 6×6 covariance, and would partially *cancel* a user asking for "happy and danceable" because those heads are correlated. |

### 3.5 Finding B is a declared limitation, not a solved problem

With r(arousal, mood_relaxed) = −0.901, per-head standardization gives the energy/relaxation axis
roughly double the weight of an independent one. I recommend **declaring this in the
`CatalogueScale` constant as a comment with the measured r, and not fixing it now.** It is a
chosen, documented trade-off rather than an accident — which is the bar the status quo fails. If
the team later wants concept-level balance, the cheap next move is to drop or merge `mood_relaxed`
against `arousal`, not to introduce a covariance matrix. That is a separate ticket with its own
evidence requirement.

---

## 4. `MAX_DISTANCE` and the 0..1 validation — dispatch constraint 3

### 4.1 The validation stays

`mood_vector.rb:9` validates all six heads into 0..1. **Keep it unchanged.** `R` is derived, not
stored, so nothing in the recommendation path ever writes an out-of-range value to these columns.
This is the main structural payoff of deriving rather than storing `R`: the display invariant,
the LLM interchange format, `VibeOverride`, and the JS `clamp01` all keep one coherent meaning.

Note also that the query-side `MoodVector.new` at `query_understanding_client.rb:37` and
`query_understanding_cache.rb:34` is never saved, so the validation never runs on it anyway.
Constraint 3's concern about validation is therefore confined to the album side, and the album
side does not move.

### 4.2 `MAX_DISTANCE` is retired

In `R` there is no finite maximum distance, so `mood_vector.rb:4` cannot survive as-is. Replace
the `d / MAX_DISTANCE` normalizer at `candidate_retrieval.rb:41` with a bounded, monotone squash:

```
mood_term = d_z / (d_z + REFERENCE_DISTANCE)
```

`REFERENCE_DISTANCE` = the measured median pairwise standardized distance over the grounded
catalogue (measure it — do not assume `sqrt(12)`, because Finding B means the heads are not
independent and the analytic value will be too large). The term is in [0, 1), monotone everywhere
— no clamp, so no loss of ordering in the tail — and `mood_term = 0.5` at a typical distance,
which is an interpretable calibration point.

### 4.3 The trap in §4.2 — this silently reweights mood against the facets

`MOOD_VECTOR_WEIGHT = 0.20` (`candidate_retrieval.rb:4`) was tuned against today's mood term.
Today's term averages roughly 0.30: typical per-musicnn-head difference ≈ 0.37, so
`d ≈ sqrt(4 · 0.137) ≈ 0.74`, divided by `sqrt(6) = 2.449`. Under the §4.2 squash calibrated at
the median, the term averages 0.5. **That is a ~1.7× increase in mood's influence over the facet
embeddings, delivered as a side effect of fixing the intra-mood weighting.**

This must be an explicit, stated recalibration. Either pick `REFERENCE_DISTANCE` so the term's
mean matches today's, or — cleaner — keep `REFERENCE_DISTANCE` at the interpretable median and
lower `MOOD_VECTOR_WEIGHT` to ≈ 0.12 so total mood influence is held constant. **Acceptance
criterion: the mean of `MOOD_VECTOR_WEIGHT · mood_term` over a fixed query set must be within
10 % of its pre-change value.** Measure it; do not eyeball it.

I would rate shipping §3 without §4.3 as an IMPORTANT-severity defect. It is the kind of change
that looks like a pure improvement and quietly moves a second dial.

---

## 5. Migration and backfill

**The migration is not the fix.** §3 and §4 require no schema change and capture 100 % of the
measured harm. The migration below buys two different things, both real, neither urgent:

1. A trace for the live emomusic clamp (§0.2a), which today is silent and unrecoverable.
2. The ability to change the emomusic → 0..1 mapping later without re-extracting the catalogue.

If the owner wants the migration first, they will be paying migration cost for a change that by
itself improves no recommendation. I recommend against that ordering and say so in §7.

### 5.1 Columns — additive only, on `mood_vectors`

| column | type | null | notes |
|---|---|---|---|
| `raw_valence` | float | yes | album mean of raw emomusic valence (nominal 1..9, admissible −3..13) |
| `raw_arousal` | float | yes | same |
| `valence_saturated_tracks` | integer | yes | **no default** — see §5.3 |
| `arousal_saturated_tracks` | integer | yes | **no default** |
| `contributing_track_count` | integer | yes | not persisted anywhere today; required to read the counters, and required by issue #30 option (b) |
| `scale_version` | string | yes | provenance of the 0..1 columns |

**No raw columns for the four musicnn heads.** Their `sanity_range` is hard 0..1, the mapper's
clamp is unreachable, and the stored value *is* the raw value. Duplicating them would be pure
redundancy. (This changes if sonance#15 lands and removes the hard veto — that is precisely the
issue #30 hazard, and at that point the four heads need saturation counters too, but still no raw
columns, since a softmax outside 0..1 is a fault rather than a value. See §6.)

Add a check constraint on `raw_valence`/`raw_arousal` against the gem's `sanity_range`, and extend
`config/initializers/sonance_registry.rb:8-14` to assert `sanity_range` as well as `native_range`
— read it from the registry rather than hardcoding a second literal, since a literal is how the
`native_range` / `sanity_range` gap went unnoticed in the first place.

### 5.2 What is recoverable

- **Four musicnn heads: fully recoverable, trivially.** Stored value = raw value.
- **Two emomusic heads: exactly recoverable via `raw = v·8 + 1`** for any album where no
  contributing track was clamped. The transform is affine, and `aggregate`
  (`mood_grounding_service.rb:177-185`) takes an arithmetic mean, which commutes with an affine
  map — so inverting the album mean gives the mean of the raw track values exactly.
- **Clamped rows: unrecoverable.** Saturation left no trace, and album-level means hide per-track
  saturation entirely (Baton's caveat 1 is correct and load-bearing). The `spread` jsonb is a weak
  and insufficient proxy: `spread == 0.0` on every head means *either* one contributing track *or*
  perfectly identical tracks, and cannot recover the count.

### 5.3 How to mark the loss — the part that matters

**Backfilled rows must be able to say "unknown", not "zero".** If `*_saturated_tracks` ships with
`default: 0` and the backfill leaves it, every legacy row asserts "no track was clamped" — the
exact claim we cannot make. That is a lie encoded in the schema, and it will be read as fact by
whoever next audits this.

Therefore: **nullable, no default. NULL means unknown.** Backfill sets the raw columns by
inversion and leaves the counters NULL. `scale_version` is set to `legacy_v0_inverted` for
backfilled rows and `v1_measured` for rows written by the new mapper. Any future analysis that
needs saturation-clean data filters on `scale_version = 'v1_measured'`, and gets a correct answer
instead of a confidently wrong one.

`MoodGroundingService#default_attrs` (`:47`) must set the raw columns to NULL and
`scale_version` to `llm_only` — an `llm_only` row's 0.5s are a neutral placeholder, not a
measurement, and must not be inverted into a fake raw 5.0.

### 5.4 Re-extraction — gate it on a measurement, do not schedule it

Re-downloading previews and re-running Essentia across the catalogue is the only way to get clean
raw values for already-clamped rows. **Do not commit to it up front.** The realized emomusic band
is 3.20..6.66 raw, comfortably inside 1..9, which predicts a near-zero per-track clamp rate.

Instead: ship the counters, re-enrich a sample of ~50 albums, and read the actual per-track
saturation rate off `v1_measured` rows. If it is ~0, the legacy inversion is sound and full
re-extraction is not justified. If it is material, you now have a number to justify the cost with.
Spending a catalogue re-extraction on a hypothesis is the wrong trade when the hypothesis is
cheaply testable.

---

## 6. Issue #30 — I partly agree with the owner, and partly not

The owner's reading is that the directive dissolves #30: retain the true value in the
recommendation path, make clamping display-only, and you neither skip the track nor poison the
recommendation.

**That is correct for the two emomusic heads.** Their `range_kind` is `:nominal` and the gem
admits −3..13. A value of 0.6 or 9.4 is a *plausible model output on a nominal scale*, carrying
real signal. Retaining it raw and projecting for display is exactly right, and it fixes a live
silent-clamp path that #30 does not currently cover.

**It does not dissolve for the four musicnn heads, which are what #30 is actually about.** Those
are mean-reduced softmax probabilities. A softmax output above 1.0 or below 0.0 is not a genuine
extreme carrying signal — it is float error or a broken graph. "Retaining the true value" of a
softmax at 1.4 retains a bug, not accuracy. So for those four, the answer is neither #30's (a) nor
its (b) as framed:

> **Recommended #30 policy: accept a tight float-tolerance band (|excess| ≤ 1e-6) and clamp within
> it silently; treat anything beyond as a track-level failure, i.e. option (a) with an epsilon.
> Additionally, persist `contributing_track_count` (§5.1) so a silent shrink in contributing tracks
> is visible — which is the genuinely good half of option (b), and is worth having under either
> policy.**

And separately: **#30 should be widened to name the emomusic clamps**, which are the only ones
that can fire under the currently pinned gem. As written it reads as though no clamp is live
today. That is false.

---

## 7. Sequencing

**Ship in this order. The first item is the whole fix.**

1. **Owner sign-off on the restatement in §2.** Blocking. Everything below assumes "deliberate and
   reviewable" rather than "raw". If the owner holds the literal reading, stop and re-plan — I do
   not want an implementer discovering the 65/35 flip mid-ticket.
2. **Measure standardized `REFERENCE_DISTANCE` (`d_z`) as the median pairwise distance over
   grounded catalogue rows, and measure the current mean mood term on a fixed query set.** This is
   the baseline §4.3's acceptance criterion is measured against; it must be captured *before* any
   behaviour changes. *(Corrected on 2026-08-14: the earlier sentence omitted "standardized" and
   incorrectly implied query-set measurement for `REFERENCE_DISTANCE`.)*
3. **`MoodVectors::CatalogueScale`** — the frozen `(μ, σ)` table, `VERSION`, the declared Finding B
   limitation, and the drift spec. No behaviour change yet.
4. **`R` in the metric** — the standardized distance, the §3.3 probit bridge, the §4.2 squash
   replacing `MAX_DISTANCE`, and the §4.3 `MOOD_VECTOR_WEIGHT` recalibration **in the same commit**.
   Splitting 4 from the recalibration is how the silent reweighting ships.
5. **Prompt reword** at `query_understanding_client.rb:7-13`. Independent, small, do it any time
   after 4.
6. **Decide #30** per §6, and widen it to cover emomusic. Must land before any sonance repin.
7. **The migration** (§5) — additive columns, mapper returns raw + saturation, aggregate carries
   them, backfill by inversion with `legacy_v0_inverted`.
8. **Sample re-enrichment** (§5.4) and the decision on catalogue re-extraction, gated on its result.
9. **Optional, separate ticket:** Finding A — a percentile-based `VibePhraseBuilder` /
   `MoodDescriptor`, so valence and arousal stop being invisible in the UI copy and in the
   emotional facet embedding. Note this one *does* change the embedding facet and therefore
   requires re-embedding; scope it accordingly.

---

## 8. Blast radius

### 8.1 Changed by §3–§4 (the metric fix — no migration)

| file:line | change |
|---|---|
| `app/models/mood_vector.rb:4` | `MAX_DISTANCE` retired |
| `app/models/mood_vector.rb:11-13` | `distance_to` → standardized distance (or moved out; see note) |
| `app/models/recommendations/candidate_retrieval.rb:4` | `MOOD_VECTOR_WEIGHT` recalibrated per §4.3 |
| `app/models/recommendations/candidate_retrieval.rb:41` | mood term: standardized distance + squash |
| `app/models/mood_vectors/catalogue_scale.rb` | **new** — frozen (μ, σ), `REFERENCE_DISTANCE`, `VERSION` |
| `app/models/mood_vectors/query_projection.rb` | **new** — probit bridge |
| `app/services/query_understanding_client.rb:7-13` | prompt reworded to ask for relative intensity |
| `spec/models/mood_vector_spec.rb` | distance/`MAX_DISTANCE` expectations |
| `spec/models/recommendations/candidate_retrieval_spec.rb` | scoring expectations |
| `spec/models/recommendations/pipeline_spec.rb` | downstream ordering |
| `spec/requests/recommendations_spec.rb` | end-to-end ordering |
| `spec/models/mood_vectors/catalogue_scale_spec.rb` | **new** — the drift guard |

*Note on placement:* per `CLAUDE.md`, domain logic belongs on the model, and new SRP classes go
under `app/models/mood_vectors/`. `distance_to` is a mood-vector concern and can stay on the
model; the *scale constants* and the *query bridge* are separate responsibilities and get their
own classes in that namespace. Nothing here belongs in `app/services` — there is no external I/O
boundary in any of it.

### 8.2 Changed by §5 (the migration)

| file:line | change |
|---|---|
| `db/migrate/<new>_add_raw_emomusic_to_mood_vectors.rb` | **new** — six additive columns + check constraint |
| `db/schema.rb:93-108` | regenerated |
| `app/models/mood_vectors/essentia_mapper.rb:21-28` | return raw + saturation alongside 0..1 |
| `app/models/mood_vectors/essentia_mapper.rb:43-45` | `rescale_emomusic` reports whether it clamped |
| `app/models/mood_vectors/essentia_mapper.rb:47-49` | `clamp` — epsilon policy per §6 |
| `app/services/mood_grounding_service.rb:47` | `default_attrs`: raw NULL, `scale_version: llm_only` |
| `app/services/mood_grounding_service.rb:114-115, 127-128` | mapper call sites carry the new shape |
| `app/services/mood_grounding_service.rb:172-185` | `aggregate`: mean the raw heads, sum the counters, record `contributing_track_count` |
| `app/models/mood_vector.rb:9` | add raw-column validations against the registry sanity range |
| `config/initializers/sonance_registry.rb:8-14` | assert `sanity_range` too, from the registry |
| `app/madmin/resources/mood_vector_resource.rb` | expose the new attributes |
| `app/jobs/enrich_album_job.rb:26` | no code change; new attrs flow through `update!` — verify |
| `spec/models/mood_vectors/essentia_mapper_spec.rb` | new return shape, saturation reporting |
| `spec/services/mood_grounding_service_spec.rb` | aggregate carries raw + counters |
| `spec/factories/mood_vectors.rb` | new columns |

### 8.3 Verified unchanged — display keeps 0..1

Each of these I opened and confirmed reads only the six 0..1 columns:

- `app/models/mood_vectors/vibe_phrase_builder.rb:12` (`NEUTRAL`), `:13`
  (`DISTINCTIVE_THRESHOLD`), `:39` (0.6 split) — unchanged, but see Finding A / step 9.
- `app/javascript/controllers/library_vibe_map_controller.js:165, 178` (`clamp01`) — unchanged.
- `app/models/vibe_override.rb` and `db/schema.rb` `vibe_overrides` — unchanged. Note for the
  record: overrides feed `Albums::VibeMapBuilder#moods` and `AlbumsController` only.
  `CandidateRetrieval` reads `album.mood_vector` directly, so **user overrides do not affect
  recommendations today**. That is a pre-existing product question, not a regression, and out of
  scope here — but if it ever changes, the override path needs the same projection.
- `app/models/albums/vibe_map_builder.rb:14-47` — unchanged.
- `app/views/albums/_vibe_map.html.erb:18, 27` — unchanged.
- `app/models/query_understanding_cache.rb:15-20, 33-39` — unchanged, and stays valid across a
  scale-version bump (§3.3).
- `app/madmin/resources/{vibe_override,query_understanding_cache}_resource.rb` — unchanged.

### 8.4 Explicitly NOT display-only, contra the dispatch

- `app/services/mood_descriptor.rb:10-13, 18-19, 23-24` → `app/services/album_embedding_service.rb:41-45`
  → the `emotional` facet at `candidate_retrieval.rb:3`. Recommendation input. Threshold-degenerate
  per Finding A. Leave it alone in steps 1–8 (changing it forces re-embedding); address in step 9.

---

## 9. Things I would flag as bad ideas

1. **Storing raw and feeding raw into an unweighted metric.** §2. Measurably worse: 65/35 flipped,
   arousal alone at 44 %, on the head that duplicates `mood_relaxed` at r = −0.901.
2. **Recomputing `(μ, σ)` from the live catalogue at scoring time.** Makes recommendations
   irreproducible and unspeccable, and turns "we added an album" into "everyone's results moved".
3. **Shipping the standardized metric without recalibrating `MOOD_VECTOR_WEIGHT`.** §4.3. Silently
   multiplies mood's influence over the facet embeddings by ~1.7×.
4. **`default: 0` on the saturation counters.** §5.3. Encodes a false claim about every legacy row.
5. **Scheduling a catalogue re-extraction before measuring the saturation rate.** §5.4. The data we
   have predicts the rate is ~0.
6. **Doing the migration first because the ticket is labelled "will require a migration".** The
   migration is genuinely useful and genuinely not the fix. Ordering it first delays the actual
   repair behind schema work and risks the repair being descoped once the migration has shipped and
   the ticket "feels done".
7. **Whitening / Mahalanobis as the first answer to Finding B.** Correct statistics, wrong
   engineering: opaque metric, stored covariance, and it would partially cancel a user asking for
   two correlated moods at once. Declare the limitation; revisit with evidence.

---

## 10. Summary of my position

- Baton's measurement is **correct and reproduced exactly**.
- The owner's *goal* is correct; the owner's *mechanism* (raw numbers in the metric) is
  **measurably a regression** and I am asking for a restatement before work starts (§2).
- The measured harm is **entirely fixable without a migration** (§3–§4).
- The migration is worth doing, for **different and lesser reasons**, and should come **after** the
  fix (§5, §7).
- Issue #30 **dissolves for emomusic and does not dissolve for musicnn**; the right policy for the
  four hard heads is skip-with-epsilon, plus persisting `contributing_track_count` (§6).
- Two unanticipated findings: the compression **degrades display too** (valence is distinctive on
  10 % of albums), and the six heads are **not six dimensions**
  (r(arousal, mood_relaxed) = −0.901), which any equalizing scheme must declare (§0.3).
