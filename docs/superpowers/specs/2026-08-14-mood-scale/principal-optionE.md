# MOOD-SCALE — Option E implementation plan (Tier 1, plan only)

**Author:** Keystone (Principal Engineer)
**Date:** 2026-08-15
**Repo:** /Users/lukeolson/projects/vibe-doctor · basis:
`docs/superpowers/specs/2026-08-14-mood-scale/principal-rereview.md` (committed)
**Assumes:** `MoodVectors::CatalogueScale` is being removed from PR #38. Nothing below references it.

---

## Recovery provenance — read this first

`/tmp/maestri-reviews` was cleaned by the OS on 2026-08-15 and the authoritative copy of this plan
was believed lost. **It was not.** A complete, untracked copy survived on disk in the
`feat/mood-scale-option-e` worktree at this path. Sections 0–10 below are that copy, **unmodified**.
Nothing in them was rewritten from memory.

**What is what, so a reader knows the standing of each claim:**

| standing | which parts |
|---|---|
| **SURVIVED VERBATIM** — the original file, byte-for-byte | §§0–10 in full, including the complete G1–G11 gate table that was believed lost |
| **RE-VERIFIED against sources after recovery** — re-derived on 2026-08-15 from the committed fixture and the built code, not taken on trust | every numeric claim in §1.2, §1.4, §3.4 and the G1/G2/G8/G10 gate values; see §11.1 |
| **RECONSTRUCTED** | nothing. No section was rebuilt. |
| **REMEMBERED but not re-derived** | nothing in §§0–10. The two figures I could not re-check from a surviving source are named explicitly in §11.4. |
| **NEW since the original plan** | §11 only — two added gates (**G12** and **G13**), one numeric refinement, and the post-recovery verification record |

This file is now **in the repository**, which is where it should have been from the start.

---

## 0. The decision that removes the largest risk in this plan

**Layer 1 is applied at SCORING TIME, to the album side only. No stored value changes. No mapper
change. No migration. No backfill. No re-embedding.**

Baton flagged re-embedding as the potentially largest hidden cost. It is zero, and it is zero
*because of this decision* — which is why it is stated first, before anything else, and why §5
rejects the alternative explicitly. If anyone proposes implementing Layer 1 in
`MoodVectors::EssentiaMapper` instead, that single change re-introduces a full-catalogue
re-embed, a migration, a backfill, and a break in `VibeOverride` semantics. **It must be refused.**

Everything in §§1–4 follows from this.

---

## 1. Layer 1 — the band

### 1.1 Evidence anchoring the choice (independently verified by Baton)

- `sonance` `registry.rb:249-251` declares emomusic `range_kind: :nominal`,
  `native_range: (1.0..9.0)`, `sanity_range: (-3.0..13.0)`. **The gem author treated 1..9 as an
  annotation scale, not an output bound** — the enforced band is 2× wider on each side.
- The four musicnn heads (`registry.rb:266-268`, `range_kind: :hard`, `0.0..1.0`) **saturate**:
  danceability 0.001110..1.000000, mood_acoustic 0.000002..0.999145.
- emomusic realized **raw album-mean** span is **2.64 of 8 units** (valence 3.7508..6.3912) and
  **3.47** (arousal 3.1973..6.6632). Both far under the 6.0 falsifier pre-registered in the
  re-review §15.3.

Classifiers spread, regressors shrink. That asymmetry is architectural, and the band correction
exists to undo it.

### 1.2 The measured trade-off

Per-head share of expected squared distance over the 321 grounded rows, equal Layer 2 weights:

| band | factor | valence | arousal | dance | acoustic | happy | relaxed | **imbalance** |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1.0..9.0 *(today)* | 1.000 | 0.88 % | 1.91 % | 28.25 % | 25.94 % | 18.23 % | 24.79 % | **31.95** |
| 2.0..8.0 | 1.333 | 1.54 % | 3.32 % | 27.65 % | 25.39 % | 17.84 % | 24.26 % | 17.97 |
| 2.5..7.5 | 1.600 | 2.17 % | 4.68 % | 27.07 % | 24.86 % | 17.47 % | 23.75 % | 12.48 |
| **3.0..7.0** ← | **2.000** | **3.26 %** | **7.04 %** | 26.07 % | 23.93 % | 16.82 % | 22.87 % | **7.99** |
| 3.2..6.7 | 2.286 | 4.13 % | 8.92 % | 25.27 % | 23.20 % | 16.31 % | 22.17 % | 6.12 |
| per-head tight | — | 7.03 % | 8.80 % | 24.46 % | 22.46 % | 15.79 % | 21.46 % | 3.48 |

Calibrated album coordinate range vs the LLM's 0..1 (the reachability problem):

| band | valence | arousal |
|---|---|---|
| 1.0..9.0 *(today)* | 0.344 .. 0.674 | 0.275 .. 0.708 ← LLM's 0.9 unreachable |
| 2.5..7.5 | 0.250 .. 0.778 | 0.139 .. 0.833 |
| **3.0..7.0** | **0.188 .. 0.848** | **0.049 .. 0.916** |
| 3.2..6.7 | 0.157 .. 0.912 | **−0.001** .. 0.989 ← zero margin already |

### 1.3 Recommendation: **a single shared band of 3.0 .. 7.0**, and the argument for it

**Choose the band for SAFETY and REVIEWABILITY, not for balance.** Balance is Layer 2's job. This
is the reframing that makes the choice easy: Layer 1's job is to remove the *unit accident*; how
much each head should then matter is an explicit product decision the owner makes. Trying to make
Layer 1 do both is how the withdrawn design went wrong in the first place.

Five arguments, in order of weight:

1. **It is symmetric about 5, so the neutral point is preserved exactly.** Stored 0.5 → raw 5.0 →
   calibrated `(5−3)/4 = 0.5`. This holds for any band with `lo + hi = 10`, and **fails for the
   tight band** (3.2..6.7 maps 0.5 → 0.5143). This matters concretely:
   `MoodGroundingService#default_attrs` (`mood_grounding_service.rb:47`) writes 0.5 as the neutral
   `llm_only` placeholder. Under a non-symmetric band those rows silently acquire a small positive
   emomusic bias. **This is a correctness constraint I did not anticipate in the re-review, and it
   eliminates the tight band on its own.**
2. **Round numbers are reviewable; measured numbers are only transcribable.** "3 to 7 on a 1-to-9
   scale" can be held in a reviewer's head and argued with. `3.7508..6.3912` cannot — it can only
   be copied, and this ticket's failure history is six wrong transcribed constants.
3. **One band, both heads.** Both are emoMusic regression heads from the same model with the same
   output characteristics. A per-head band would encode a per-head *distributional* fact — exactly
   the category of thing Option E exists to remove. One band = one decision.
4. **Reachability is solved with room to spare.** Calibrated arousal reaches 0.916 and valence
   0.848, so an LLM emitting 0.9 is now a reachable target. The tight band already produces
   −0.001 on the dev data, i.e. it is *at* its limit before a single new album arrives.
5. **The residual 7.99× is a chosen number, handed to the owner.** If they want closer to parity,
   they raise the valence and arousal weights in Layer 2 — one line, reviewed, no measurement.

### 1.4 What happens outside the band — **no scoring-time clamp**

**Recommendation: do not clamp the calibrated coordinate.** An album whose raw emomusic falls
outside 3.0..7.0 produces a calibrated value slightly below 0 or above 1, and that is correct.

- **Clamping would destroy ordering among exactly the extreme albums the correction exists to
  serve** — two albums at raw 2.8 and 2.5 would both become 0.0 and be indistinguishable. Silent
  saturation with no trace is the original complaint that opened this ticket; re-introducing it at
  scoring time would be perverse.
- **The metric does not require [0, 1].** Only the bound on `MAX_DISTANCE` does, and that becomes a
  *nominal* normalizer (§2.3). Over the 12-query × 321-row fixture the **maximum mood term is
  0.755** — the nominal bound of 1.0 is not approached.
- **The margin question largely dissolves once nothing clamps.** Arousal's observed album-mean min
  of 3.1973 sits only 0.197 above a 3.0 floor, which would be uncomfortably thin *if* crossing it
  caused saturation. It does not; it produces a small negative coordinate and correct ordering.
- Exposure is bounded by the gem: `sanity_range` −3..13 caps the calibrated coordinate at
  [−1.5, 2.5] in the absolute worst case. Gate G2 asserts no clamp; the §6 instrumentation records
  the max observed term so the nominal bound is monitored rather than assumed.

**Note the scope carefully:** this is about *album means*, which is what `mood_vectors` stores and
what Layer 1 reads. Per-**track** clamping happens earlier, inside the mapper, and is untouched by
this plan — see §8.

### 1.5 Does the answer change if production spans wider?

Partly, and it is cheap to check. A wider production span makes the band *more* right, not less:
more albums land outside 3.0..7.0, which under a no-clamp design simply means a wider calibrated
range and better per-head balance. The band only becomes wrong if production emomusic spans so
wide that the correction becomes unnecessary — which is precisely the pre-registered falsifier
(raw span > 6.0 units). **Nothing about the band choice needs to wait for production data**, and
§7's instrumentation plus the production query will confirm or refute it after the fact.

---

## 2. Layer 2 — weights as a product surface

### 2.1 Where they live

`app/models/mood_vectors/head_weights.rb` — a new SRP class in the established namespace
(`CLAUDE.md`: domain logic on models, not `app/services`; no external I/O boundary here).

```
WEIGHTS = { valence: 1.0, arousal: 1.0, danceability: 1.0,
            mood_acoustic: 1.0, mood_happy: 1.0, mood_relaxed: 1.0 }.freeze
```

Six numbers, one file, all equal by default. **The owner changes them in a PR without touching any
scoring logic** — the scoring path reads `HeadWeights.for(head)` and never contains a literal.

### 2.2 What validates them

Validated at load (an initializer-style assertion, in the class body), failing loudly:

| check | rationale |
|---|---|
| key set **exactly equals** `MoodVector::MOOD_HEADS` | catches a typo'd key, a missing head, and an extra head in one assertion. Use set equality, **never** positional iteration — `MOOD_HEADS` and any other head list must be compared by key (re-review §0.2 found `mood_happy`/`mood_relaxed` swapped between two existing constants) |
| every value is a **finite, positive Float** | a zero silently disables a head; a negative inverts it into an anti-preference; a NaN poisons every score |
| the hash is **frozen** | prevents runtime mutation |

**Explicitly NOT validated: the sum.** The metric is invariant under uniform scaling of all
weights — `d = √(Σ k·wₕ·Δₕ²)` and `MAX = √(Σ k·wₕ)` both scale by `√k`, so the term is unchanged
(gate G4 proves this). A "weights must sum to 6" rule would be cargo-cult: it constrains a
quantity that has no effect, while giving false assurance about the quantity that does. Only
*relative* weights matter, and only §5's G6 constrains those.

### 2.3 What stops a silent typo — the honest answer

Arity, sign and key-set checks catch a *malformed* table. They do **not** catch `10.0` typed for
`1.0` on danceability: the key set is intact and the value is a positive float.

**What catches it is gate G6, the no-dominant-head gate.** With `w_danceability = 10.0`,
danceability's share of mood distance rises to roughly 72 % and the imbalance ratio exceeds 200,
against a ceiling of 12. **The gate that would have caught the original defect is the same gate
that catches a weight typo** — which is the strongest argument for making it a permanent, running
gate rather than a one-time check.

**Operational rule, and it is load-bearing:** because a Layer 2 change alters relative weights, it
changes the mood term's dispersion. **Both G6 and the G7 calibration gate must run on every weight
change, and `MOOD_VECTOR_WEIGHT` must be re-derived if G7's ratio leaves its band.** The gates are
not step-4 scaffolding; they are the permanent contract on this product surface.

### 2.4 `MAX_DISTANCE` — how it returns

It returns as `√(Σ wₕ)` — **but not as `MoodVector::MAX_DISTANCE`, and never as a literal.** It
becomes `MoodVectors::HeadWeights.max_distance`, **derived from `WEIGHTS` at call time**, so it
cannot desync from the weights it normalizes. A hardcoded `Math.sqrt(6)` would be correct today
and silently wrong the moment the owner edits one weight — exactly the failure mode this plan
exists to eliminate.

With all weights 1.0 it evaluates to `√6 ≈ 2.449`, numerically identical to today's constant. That
is a coincidence of the default, not a reason to hardcode it. **G4 proves the derivation is live**
by doubling every weight and asserting the mood term does not move.

---

## 3. What is deleted, what returns, and the exact call sites

### 3.1 Deleted

| item | disposition |
|---|---|
| the probit bridge / `QueryProjection` | **Deleted.** Layer 1 makes calibrated album coordinates span 0.049..0.916, so the LLM's 0..1 is directly comparable. The problem it solved no longer exists. |
| `REFERENCE_DISTANCE` | **Deleted.** No z-space, no squash. |
| the `d/(d+R)` squash | **Deleted.** Coordinates are ~0..1, so a finite nominal maximum exists again. |
| `MoodVector::MAX_DISTANCE` (`mood_vector.rb:4`) | **Deleted** from `MoodVector`; the concept returns as `HeadWeights.max_distance` (§2.4). |
| `MoodVector#distance_to` (`mood_vector.rb:11-13`) | **Deleted.** It is the old metric, and `a.distance_to(b)` hides the deliberate asymmetry (album calibrated, query not). The new entry point takes both sides explicitly. |
| `MOOD_VECTOR_WEIGHT = 0.24` | **Void.** It belonged to the withdrawn mechanism. |

Confirmed by `git grep` at `d99c262`: `MAX_DISTANCE` and `distance_to` have **exactly one reader
each**, both at `candidate_retrieval.rb:41`, and **zero spec references**.

### 3.2 `mood_vector.rb` after the change

Lines 4 and 11–13 are removed. `MOOD_HEADS` (`:3`), the `mood_source` inclusion validation (`:8`),
the **0..1 numericality validation (`:9`, unchanged and load-bearing)**, and `vibe_phrase` (`:15-17`)
all stay. The model goes back to being a persistence + display object with no metric on it.

### 3.3 `candidate_retrieval.rb:41` after the change

```
mood_term = MoodVectors::MoodDistance.term(album_mood: album.mood_vector,
                                           query_mood: @understanding.mood_vector)
```

where `MoodVectors::MoodDistance.term` computes, over `MoodVector::MOOD_HEADS` keyed by name:

```
d    = √( Σ  HeadWeights.for(h) · ( HeadCalibration.album_coordinate(mood, h) − query.send(h) )² )
term = d / HeadWeights.max_distance
```

Line 42 keeps its shape: `facet_distance + (MOOD_VECTOR_WEIGHT * mood_term)`.

### 3.4 `MOOD_VECTOR_WEIGHT` — **stays 0.20**, with the derivation

Measured over the frozen 12-query × 321-row fixture, band 3.0..7.0, equal weights:

| quantity | value |
|---|---|
| OLD mean within-query sd of the mood term | **0.095101457** *(matches the frozen baseline exactly)* |
| NEW mean within-query sd of the mood term | **0.098886389** |
| dispersion-matched weight `W = 0.20 × OLD/NEW` | **0.192345** |
| **residual at the unchanged 0.20** | **+3.98 %** |
| per-query dispersion ratio at `W = 0.192345` | **[0.9487, 1.0717]** |
| OLD / NEW mean mood term | 0.344698 / 0.352078 |

**Decision: keep `MOOD_VECTOR_WEIGHT = 0.20`, and record `0.192345` and the +3.98 % residual in a
comment beside it.** This is a deliberate calibration decision with a number attached, not an
omission. Rationale: 3.98 % is well inside the uncertainty of a 12-query synthetic set measured on
a single user's library, and changing a tuned product constant for a 4 % effect adds churn without
adding confidence.

**Note how gentle Option E is compared with the withdrawn design.** Its per-query dispersion ratio
is [0.9487, 1.0717] — a ±7 % band. The probit/z-space design's was [0.65, 1.36]. Option E is very
nearly blend-neutral, which is a strong independent signal that it changes the *right* thing (which
head matters) without disturbing the *wrong* thing (mood versus facets).

**The §4.3 dispersion insight survives intact and is metric-agnostic**: ranking depends on the
within-query dispersion of `W · mood_term`, not on its mean. The acceptance gate (G7) is
dispersion-based. The gate band is **[0.95, 1.06]**, which accommodates the +3.98 % residual and
still fails a ±20 % weight mutation (0.24 → ratio 1.248).

---

## 4. The second channel — **stays exactly the same. Zero re-embedding.**

**Settled: neither better nor worse. Unchanged, and it costs nothing.**

The chain is `MoodDescriptor.render` (`mood_descriptor.rb:10-13, 18-19, 23-24`) →
`AlbumEmbeddingService#emotional_text` (`album_embedding_service.rb:41-45`) → the `emotional` facet
(`candidate_retrieval.rb:3`, weight 0.15). Both read **stored** `mood_vector` values.

**Layer 1 never touches a stored value** (§0). Therefore:

- No stored `valence` changes, so **no album crosses `MoodDescriptor`'s 0.6/0.4 thresholds**.
- No `emotional_text` string changes, so **no embedding changes**.
- **No re-embedding. Not of 321 albums, not of one.**
- `VibePhraseBuilder`'s absolute thresholds, the vibe map, `VibeOverride`, and
  `default_attrs` are all likewise untouched.

### 4.1 The inconsistency, restated honestly

The two channels already disagree today and will continue to: the Euclidean channel now takes
valence seriously (3.26 % → up from 0.88 %, and adjustable via Layer 2), while the embedding
channel still applies absolute 0.6/0.4 thresholds to compressed stored values, firing a valence
phrase on only 32 of 321 albums. **Option E does not widen this gap the way the withdrawn probit
design would have** — that design introduced *percentile* semantics into one channel, a much
larger divergence than a band recalibration.

**This is a real but unchanged limitation, and it must be named in the design doc rather than
discovered later.** Closing it means applying the same 3.0..7.0 band to `MoodDescriptor`'s
thresholds — which changes `emotional_text`, and **that is where the full-catalogue re-embed
appears.** It is a separate, cost-bearing ticket. Costing it now so it is never a surprise:
321 albums × 4 facet embeddings via `text-embedding-3-small`, one full enrichment pass, plus the
risk that every album's emotional facet moves at once.

### 4.2 The alternative that must be refused

Implementing Layer 1 inside `MoodVectors::EssentiaMapper` — i.e. changing what gets *stored* —
would be a smaller diff and is the obvious-looking shortcut. It would require: a migration, a
backfill of 321 rows, a full re-embed (§4.1), a redefinition of every display threshold, and a
silent break in the meaning of already-stored `VibeOverride` rows, which were entered by users
against the old scale and have no version marker. **Reject it. The scoring-time placement is the
design, not an implementation detail.**

---

## 5. Test strategy — every gate with the mutation that must be executed and pasted

This ticket has shipped six verification artifacts that could not fail. **A green suite proves
nothing until a mutation says otherwise.** For each gate the implementer must run the named
mutation and paste the failure into the PR; a gate whose mutation was not executed does not count.

All gates run off a **committed fixture** (§5.1) so they execute in CI, where no dev database
exists. Tag-excluding a gate for want of a database is the "green suite compatible with a broken
gate" failure and is not acceptable.

| id | gate | mutation that must make it fail |
|---|---|---|
| **G1** | `HeadCalibration`: band is 3.0..7.0; the four musicnn heads pass through **unchanged**; the two emomusic heads map by the exact affine (stored 0.344 → 0.188, 0.674 → 0.848) | set the band to 1.0..9.0; move `mood_happy` into the emomusic set |
| **G2** | **no scoring-time clamp**: a stored 0.1 (raw 1.8) yields a calibrated **−0.3**, not 0.0; a stored 0.95 yields > 1.0 | add `.clamp(0.0, 1.0)` → returns 0.0, fails |
| **G3** | `HeadWeights`: key set **equals** `MoodVector::MOOD_HEADS` as a set; all values finite and positive; hash frozen | drop `:mood_relaxed`; set `:valence` to `-1.0`; set one to `0.0` |
| **G4** | **scale invariance / live derivation**: doubling every weight leaves the mood term unchanged to 1e-12 | hardcode `max_distance` as `Math.sqrt(6)` → the term moves, fails |
| **G5** | `MoodVector.const_defined?(:MAX_DISTANCE)` is false; `MoodVector.method_defined?(:distance_to)` is false | re-add either |
| **G6** | **no head silently dominates** — *the gate that would have caught the original defect.* Over the fixture, per-head share of total mood distance; **imbalance (max/min) ≤ 12**. **Failing control:** the same computation with the declared 1.0..9.0 band **must produce 31.95 and fail**. **Passing control:** Option E **must produce 7.99 and pass** | set `w_danceability = 10.0` (imbalance > 200); revert the band to 1..9 |
| **G7** | **dispersion calibration.** Re-derive the OLD sd from the fixture using the old formula written out explicitly, assert `== 0.095101457` to 9 dp; compute the NEW sd through the shipped path; assert ratio ∈ **[0.95, 1.06]**. **Non-vacuity floor asserted first: 321 fixture rows, 12 queries, 12 non-zero sds** | `MOOD_VECTOR_WEIGHT` → 0.24 (ratio 1.248); band → 1..9 |
| **G8** | **reachability**: calibrated album arousal max over the fixture **≥ 0.85** (Option E gives 0.916; today's band gives 0.708) | revert the band to 1..9 → 0.708, fails |
| **G9** | **mood is the sole discriminator**: two albums, identical embeddings, differing moods; the mood-preferred one ranks first **and** the score gap equals the hand-computed `W · (term_a − term_b)` to 1e-9 | `MOOD_VECTOR_WEIGHT` → 0 |
| **G10** | **neutral preservation**: stored 0.5 on every head → calibrated 0.5 on every head (§1.3 argument 1) | band → 3.2..6.7 → valence yields 0.5143, fails |
| **G11** | fixture integrity: SHA-256 matches the value recorded in `baseline.md`; row count 321; query count 12 | edit one row |

**G6 and G7 are permanent, not one-time.** §2.3: they must run on every Layer 2 weight change.

**Two gates, G12 and G13, were added after recovery — see §11.2.** They separately cover
positional-read and mis-keyed-data hazards that **none of G1–G11 would catch**.

### 5.1 The fixture

`spec/fixtures/mood_scale/catalogue_snapshot.json` — the 321 grounded rows, six floats each, no
titles or artists — plus `queries.json` with the 12 vectors from `baseline.md`, generated by a
documented command with a SHA-256 recorded alongside.

**It must be labelled as one user's collection, not "the catalogue"** (re-review §8). It is a
regression corpus that pins behaviour deterministically; it is **not** a population sample, and no
constant in the shipped code may be derived from it.

---

## 6. Instrumentation — planned, not deferred

**What:** per-head realized share of mood distance, per query, on `RecommendationEvent`.

**Column:** `mood_head_shares`, `jsonb`, `default: {}`, `null: false` — six keys, six floats. Matches
the existing `blended_scores` / `rerank_scores` jsonb pattern (`pipeline.rb:38-48`).

**Computed where:** in `Recommendations::CandidateRetrieval`, which already holds the full candidate
set and every album's mood vector. It returns the shares alongside the candidates; `Pipeline`
persists them at `pipeline.rb:38-48`. No new query, no extra load.

**Cost per query:** six accumulators over N candidates — roughly `6N` float operations, ~2,400 at
N=400. Against two OpenAI round-trips, four pgvector ANN searches and a rerank call already in the
pipeline, this is unmeasurable.

**What it answers that the design otherwise cannot:** Option E deliberately does not control
per-collection variation (§8). This turns that uncontrolled quantity into an **observed** one —
within days of real traffic we learn each real user's realized per-head balance, from production,
without a migration to their data or any access we do not have. It converts the re-review's
unanswerable question into a metric, and it is the evidence that would later justify (or refuse)
the per-user option. It also records the **max observed mood term**, which is how §1.4's nominal
bound is monitored rather than assumed.

**Ships separately, immediately after Option E.** It is a migration and therefore its own Tier-1
trigger, and it is not cheaply revertable. Option E must stay independently revertable (§7), so the
two must not share a commit. It is a follow-on, not a deferral — it should be the next thing.

---

## 7. Sequencing and rollback

Only step 4 changes behaviour. Steps 1–3 are pure additions with no callers.

| # | step | independently revertable? |
|---|---|---|
| 1 | Commit the fixture + `baseline.md` addendum (`sd_old = 0.095101457`, SHA-256, generating command, **relabelled as one user's collection**) + **G11** | yes — no behaviour change |
| 2 | `MoodVectors::HeadCalibration` + **G1, G2, G10** | yes — new file, no callers |
| 3 | `MoodVectors::HeadWeights` + **G3, G4** | yes — new file, no callers |
| 4 | **The wiring commit, indivisible:** `MoodVectors::MoodDistance`; delete `MAX_DISTANCE` and `distance_to`; rewrite `candidate_retrieval.rb:41`; confirm `MOOD_VECTOR_WEIGHT = 0.20` with the §3.4 comment; add **G5, G6, G7, G8, G9**; record the §4.1 channel limitation and the §8 limitation in `docs/superpowers/specs/2026-08-14-mood-scale/` | **this is the rollback unit** |
| 5 | *(separate)* Instrumentation migration + column + computation (§6) | yes — additive column |

**Rollback:** a single revert of step 4 restores `MAX_DISTANCE`, `distance_to` and the old metric
atomically. Steps 1–3 remain in place harmlessly as unused classes and a fixture. **Do not fold
steps 2–3 into step 4 to save commits** — that is what makes the rollback clean.

**Indivisible within step 4:** the metric rewrite, the `MOOD_VECTOR_WEIGHT` confirmation, and G6 +
G7. A calibration without an executable gate is a claim, and this ticket's history is that claims
do not survive.

### 7.1 Blast radius

**Changed:** `app/models/mood_vector.rb:4` (delete), `:11-13` (delete);
`app/models/recommendations/candidate_retrieval.rb:41` (rewrite), `:4` (comment only, value stays 0.20).

**Added:** `app/models/mood_vectors/head_calibration.rb`, `head_weights.rb`, `mood_distance.rb`;
`spec/models/mood_vectors/{head_calibration,head_weights,mood_distance}_spec.rb`;
`spec/models/recommendations/mood_calibration_spec.rb`;
`spec/fixtures/mood_scale/{catalogue_snapshot,queries}.json`.

**Tests/docs only:** `spec/models/mood_vector_spec.rb` (G5);
`spec/models/recommendations/candidate_retrieval_spec.rb` (G9, plus a comment recording that its
constant-vector embeddings make both cosine distances exactly 0 — mood is the sole discriminator by
accident, and a future "fixture cleanup" would silently disable the test);
`docs/superpowers/specs/2026-08-14-mood-scale/{principal,baseline}.md`.

**Must NOT appear in the diff:** `app/models/mood_vectors/essentia_mapper.rb` ·
`app/models/mood_vectors/vibe_phrase_builder.rb` · `app/services/mood_descriptor.rb` ·
`app/services/album_embedding_service.rb` · `app/services/mood_grounding_service.rb` ·
`app/services/query_understanding_client.rb` · `app/models/vibe_override.rb` ·
`app/models/albums/vibe_map_builder.rb` · `app/models/query_understanding_cache.rb` ·
`app/jobs/enrich_album_job.rb` · `app/javascript/controllers/library_vibe_map_controller.js` ·
`app/views/albums/_vibe_map.html.erb` · `db/schema.rb` and `db/migrate/**` *(step 5 only)* ·
`config/initializers/sonance_registry.rb` · `Gemfile` / `Gemfile.lock`.
`mood_vector.rb:9` must appear **unchanged**.

---

## 8. What we still do not know — in the terms the owner will need

**Option E does not control per-collection variation, by design.** Per-head influence will still
vary from user to user, and the re-review measured how much that can be when a collection is
stylistically coherent: **up to 17× (New Wave), 11× (Ambient), and 4.5× for Electronic at n=61**,
against size-matched random controls of 2.6×, 3.7× and 1.5×.

**The owner-facing statement:** *we have removed the part of the imbalance that was an accident of
measurement units, and we have handed the remaining balance to you as six numbers you control. We
have not made every listener's library behave identically, and we cannot without per-listener
statistics — which need collections we do not have and, for new or small libraries, cannot have.*

**What the production query is still worth running for**, even though it no longer gates the design:

1. **The falsifier.** Per-user emomusic raw min/max. Any real collection with a span > 6.0 units
   falsifies the finding that opened this ticket, and Layer 1's *premise* — not just its band —
   would need rethinking. **Bring that back to me if it appears.**
2. **Band validation with real margin.** Real album-mean extremes from other users tell us whether
   3.0..7.0 has the headroom I claim. Under a no-clamp design a breach is not a failure, but it is
   information about how far the band should sit.
3. **Informing Layer 2.** If per-user spreads turn out to track each other, the owner can set the
   six weights with evidence rather than by taste — the correct way to spend a PASS (re-review
   §13.1): a one-time human input, never a live constant.

**None of these block anything.** That is the property Option E was chosen for.

---

## 9. Issue #30 under Option E — my earlier read is now **wrong**, and the calculus gets worse

My earlier position was that the owner directive dissolves #30 for emomusic and not for musicnn.
**That read depended on the recommendation path retaining the raw value. Option E does not** — it
reads the stored, declared-band value and rescales it. Any clamp that fired in
`EssentiaMapper#rescale_emomusic` (`essentia_mapper.rb:44`) has already destroyed the information
*before* Layer 1 sees it.

**So Option E does not dissolve #30 for emomusic. It amplifies the cost of an emomusic clamp.**
Layer 1 multiplies the emomusic scale by exactly 2.0, so a value damaged at the mapper carries
**twice the error into the recommendation space** that it does today. A clamp that is currently a
small distortion on a near-irrelevant axis becomes a larger distortion on an axis that now matters.

Restated for the #30 decision, unchanged in the other direction:

- **The four musicnn heads:** unchanged from my earlier read. Their `range_kind: :hard` makes the
  app's clamps dead code today; a softmax above 1.0 is a fault, not an extreme.
  **Recommendation stays: option (a) with a float-tolerance epsilon, plus persisting
  `contributing_track_count`.**
- **The two emomusic heads:** `range_kind: :nominal`, `sanity_range` −3..13, so their clamp is
  **live today** and #30 as written does not cover them. **Under Option E the argument for
  retaining raw emomusic (the design's deferred item 7) is stronger than it was**, because the
  damage is now doubled.

**Option E does not depend on #30 being decided** — it reads stored columns and changes no writer,
so the two are independent and Option E may ship first. But **#30's decider must be told that
Option E raises the stakes on the emomusic half**, and that the emomusic clamps still need to be
added to #30's scope.

---

## 10. Summary

- **Band: 3.0 .. 7.0, single and shared.** Chosen for safety and reviewability, not balance —
  balance is Layer 2's job. Decisive argument: it is **symmetric about 5**, so stored 0.5 maps to
  calibrated 0.5 and the `llm_only` neutral placeholder stays neutral. The tight band fails that
  and is eliminated on correctness, not taste.
- **No scoring-time clamp.** Ordering is preserved for the extreme albums the correction exists to
  serve; max observed mood term is 0.755 against a nominal bound of 1.0.
- **Layer 1 is scoring-time, album-side only. Nothing stored changes → ZERO re-embedding.** The
  mapper-side alternative must be refused: it would cost a migration, a backfill, a full re-embed,
  and a silent break in stored `VibeOverride` semantics.
- **`MOOD_VECTOR_WEIGHT` stays 0.20**, derivation recorded: dispersion-matched value 0.192345,
  residual +3.98 %, per-query ratio [0.9487, 1.0717]. Option E is very nearly blend-neutral.
- **`MAX_DISTANCE` returns as `HeadWeights.max_distance` = √(Σwₕ), derived live, never a literal.**
  The sum is deliberately **not** validated — the metric is scale-invariant.
- **G6 is the gate that would have caught the original defect** (imbalance ≤ 12, failing control
  31.95, passing control 7.99) **and it is also the typo defence for Layer 2.** With G7 it runs on
  every weight change, permanently.
- **Instrumentation is planned, ships separately** as its own migration, and converts the one thing
  Option E deliberately does not control into something we can observe.
- **Issue #30: my earlier read is corrected.** Option E does *not* dissolve it for emomusic; it
  **doubles** the cost of an emomusic mapper clamp. Independent of Option E, but the stakes rise.

---

## 11. Post-recovery verification (added 2026-08-15)

Everything above survived intact. This section records what I re-checked after recovery, and the
two changes re-reading the built code made me want.

### 11.1 Re-verified against surviving sources

Re-derived from `spec/fixtures/mood_scale/catalogue_snapshot.json` (321 rows, SHA-256 pinned in
`baseline.md`) and the built classes, **not** taken on trust from the recovered text:

| claim in §§0–10 | re-derived value | verdict |
|---|---|---|
| fixture per-head ranges | valence 0.3438488..0.6738990 · arousal 0.2746642..0.7078946 · danceability 0.0011096..0.9999996 · mood_acoustic 0.0000020..0.9991453 · mood_happy 0.0041317..0.9904384 · mood_relaxed 0.0003826..0.9999477 | ✓ matches §1.1 |
| G1: stored 0.344 → 0.188, 0.674 → 0.848 | `(0.344·8+1−3)/4 = 0.188`, `(0.674·8+1−3)/4 = 0.848` | ✓ |
| G2: stored 0.1 → −0.3; stored 0.95 → > 1 | −0.3 and 1.4 | ✓ |
| G8: calibrated arousal max ≥ 0.85 | raw 6.6632 → **0.9158**; old band → 0.7079 | ✓ |
| G10: neutral preservation | 3.0..7.0 → 0.5 exactly; 3.2..6.7 → 0.5143 | ✓ |
| §1.3 argument 1 (`lo + hi = 10`) | holds for 2..8, 2.5..7.5, 3..7; fails for 3.2..6.7 | ✓ |

**Built code matches the specification exactly.** `HeadCalibration` implements the 3.0..7.0 band,
emomusic-only, with no clamp. `HeadWeights` holds six equal weights, validates key-set equality
against `MoodVector::MOOD_HEADS` (as a **set**), positivity, finiteness and frozenness, and derives
`max_distance` live from `WEIGHTS`. G1–G4, G10 and G11 are present in the built specs. G11 reads the
expected SHA-256 **out of `baseline.md`** rather than from a literal in the spec, which is the right
anti-circularity structure.

The reviewers also added a gate beyond the original plan — `head_weights_spec.rb` "keeps WEIGHTS
order aligned with `MoodVector::MOOD_HEADS`" — which addresses the head-order hazard from the
step-4 review. Good addition; keep it.

### 11.2 NEW — provisional G12, binding rule, and named-data G13

**These are the two forms of one substantive gap re-reading the built artifacts exposed.**

The fixture files order their keys `valence, arousal, danceability, mood_acoustic, mood_happy,
mood_relaxed`. `MoodVector::MOOD_HEADS` orders them `… mood_acoustic, mood_relaxed, mood_happy`.
**The last two are transposed between the fixture and the head list.**

The fixture is keyed JSON, so a key-addressed read is safe. But step 4's G6 and G7 are the first
code to read the fixture *and* iterate `MOOD_HEADS`, and a positional read — `row.values`,
`values_at`, `zip`, `transpose` — silently swaps `mood_happy` and `mood_relaxed`.

**None of G1–G11 would catch it.** The two heads are both musicnn with similar spreads (σ 0.2690
and 0.3136), so a swap leaves the imbalance ratio essentially unchanged and **G6 still passes**. The
dispersion in G7 barely moves. It is precisely the silent, plausible-looking defect this ticket has
produced six times.

| id | gate | mutation that must make it fail |
|---|---|---|
| **G12 (provisional until step 4)** | **album fixture reads are key-addressed.** Load one fixture row whose `mood_happy` and `mood_relaxed` differ materially, run the constructed album vector through `HeadCalibration`, and assert the calibrated coordinate for `mood_happy` equals the value stored under the `"mood_happy"` **key** — not the value in that position. There is no query-side assertion yet because no non-tautological query fixture reader exists before step 4. | change the album fixture read to `row.values` or `values_at` → the assertion must fail. Reordering JSON keys while leaving values attached to their keys is intentionally a passing control: key-addressed reads must be order-independent. |
| **G13** | **fixture keys are paired with the correct values.** Derive `mood_happy` and `mood_relaxed` population standard deviations from the album fixture and compare them with the independently recorded named anchors in `baseline.md`; compare q02's two named query coordinates with the baseline query table. | swap the values assigned to the `mood_happy` and `mood_relaxed` keys, update the fixture SHA so G11 passes, and assert G13 fails |

**Construction rule for G6, G7 and G9, to be stated in the specs:** every fixture and query read is
`fetch("<head name>")`. No positional access to fixture rows anywhere in step 4.

G12 is not binding on step 4 while its fixture-to-vector conversion remains local to its own spec.
Step 4 must extract one shared **test-support** fixture-to-vector reader and make G6, G7, G9 and
G12 consume it. Production code must remain fixture-unaware. At that point G12 binds every
fixture-driven step-4 gate to the same named-key reader instead of certifying a private
reimplementation.

### 11.3 Numeric refinement

§1.3 states the tight 3.2..6.7 band "already produces −0.001 on the dev data". Re-derived from the
committed fixture: **arousal raw minimum 3.1973 → calibrated −0.000767**. Baton's independently
quoted −0.0007 is the more precise figure. The argument is unchanged and the conclusion is
unaffected — the tight band is already below zero before a single new album arrives.

### 11.4 What could not be re-verified, and is therefore still only remembered

Two figures in §3.4 come from a probe run against `vibe_doctor_development` whose output was
recorded only in the lost `/tmp` report:

- **NEW mean within-query sd = 0.098886389**, and therefore the dispersion-matched weight
  **0.192345** and the **+3.98 %** residual at the unchanged 0.20.
- The per-query dispersion ratio band **[0.9487, 1.0717]**.

`sd_old = 0.095101457` is safe — it is pinned in `baseline.md` and G7 asserts it to 9 dp against a
re-derivation from the fixture.

These are **not load-bearing for correctness**: the shipped decision is `MOOD_VECTOR_WEIGHT = 0.20`
(unchanged), and G7's band [0.95, 1.06] is what actually enforces the calibration. But the *stated
justification* for keeping 0.20 rests on them. **G7 re-derives all of it from the committed fixture
the first time it runs**, so the numbers become self-verifying at implementation time. If G7's
computed ratio lands outside [0.95, 1.06], trust G7 and not §3.4, and tell me.

### 11.5 Decisions I re-examined and did not change

Re-reading the built code did not move any decision. The band, the no-clamp rule, the scoring-time
placement, the zero-re-embedding conclusion, `MOOD_VECTOR_WEIGHT = 0.20`, the live-derived
`max_distance`, the deliberate non-validation of the weight sum, and the amplified (not dissolved)
issue #30 calculus all stand as written.

One thing re-reading **reinforced**: §4.2's warning about implementing Layer 1 in the mapper. The
built `HeadCalibration.album_coordinate(mood_vector, head)` takes a mood vector and returns a
derived coordinate — it never writes. That shape is the guardrail. Any future change that moves the
band into `EssentiaMapper` would delete the guardrail along with it.
