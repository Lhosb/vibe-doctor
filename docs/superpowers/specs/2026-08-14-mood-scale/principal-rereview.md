# MOOD-SCALE — architectural re-review after the owner's CatalogueScale objection

**Author:** Keystone (Principal Engineer)
**Date:** 2026-08-14
**Repo:** /Users/lukeolson/projects/vibe-doctor · tree `d99c262`

> **Verdict: the owner is right. My design is wrong as scoped, and I am withdrawing the
> CatalogueScale mechanism — not patching it.**
>
> The objection is not theoretical. I measured the mechanism with a size-matched random control and
> it reproduces strongly. **14 of 22 coherent sub-populations are more imbalanced than 90 % of
> size-matched random draws from the same library.** Worst cases: New Wave 17.2× vs control p90
> 2.6×; Ambient 11.3× vs 3.7×; Electronic — at n=61, where small-sample noise is not available as
> an excuse — **4.47× vs a control p90 of 1.48×**.
>
> My replacement recommendation removes **every catalogue-derived statistic** from the
> recommendation path. That is the point of it: it cannot go stale, cannot vary per user, and does
> not depend on the n=1-user sample that all of this ticket's numbers came from.
>
> **Second correction incorporated (production has ≥ 2 collections):** §12 pre-registers the
> decision threshold *as a number, before the data exists*; §13 gives both branches; §14 gives the
> minimum collection size, which **rules the per-user option out on its own for small collections
> regardless of divergence**; §15 argues — rather than assumes — why the 97/3 finding generalizes,
> and gives a falsification condition Baton's production query can already test.

---

## 1. First, the thing I must not do

Baton's correction arrived while I was running the measurement, and it is right on all three
counts. I confirmed the data model independently:

- `albums` is global (unique `master_id`, no `user_id`); `collection_items` is the per-user join;
  `pipeline.rb:53-55` → `pipeline.rb:18` → `candidate_retrieval.rb:34` scopes every ranking to one
  user's collection. **Ranking never touches the global pool.**
- `users` = 5, **users with a collection = 1**, `collection_items` = 322, grounded = 321.

**The "global catalogue" and "user 3's collection" are the same 321 rows.** So the per-user vs
global divergence measurement is **unmeasurable in this environment**, and a near-zero result would
be an artifact of comparing a set to itself, not evidence of agreement. I did not compute it and I
am not reporting one. This is the "zero deviation is a reading, not a verdict" trap and it would
have been the natural, wrong thing to do.

### What I measured instead, and why it is a different claim

I ran a **mechanism test**: does *coherence* — as opposed to small sample size — compress per-head
spread unevenly? That question is answerable inside one library, because it compares coherent
subsets against **size-matched random subsets of the same rows**. The random control is what makes
it a real measurement rather than a small-n artifact.

**This is evidence about a mechanism, not about real users' collections.** It does not tell us how
much a real second user would diverge. It tells us that the effect the owner described is real and
has a large magnitude when coherence is present.

---

## 2. The measurement

Per-head share of expected squared distance **inside each subset**, computed under the *global*
σ table. If global σ equalized influence inside the ranked set, every row would read 16.7 % across
and imbalance (max/min) would be 1.00.

| subset | n | valence | arousal | dance | acoustic | happy | relaxed | imbalance | random control med / p90 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **whole library** | **321** | 16.7 | 16.7 | 16.7 | 16.7 | 16.7 | 16.7 | **1.00** | — |
| Rock | 201 | 18.1 | 17.4 | 15.7 | 17.8 | 14.5 | 16.6 | 1.25 | 1.10 / 1.16 |
| **Electronic** | **61** | 25.7 | 22.7 | **8.3** | **5.8** | 18.4 | 19.1 | **4.47** | 1.27 / **1.48** |
| Pop | 57 | 19.4 | 16.5 | 16.1 | 14.6 | 15.5 | 18.0 | 1.33 | 1.30 / 1.48 |
| Jazz | 54 | 17.8 | 16.0 | 17.7 | 13.2 | 20.4 | 14.9 | 1.55 | 1.31 / 1.51 |
| Folk/World/Country | 45 | 12.2 | 14.2 | 23.5 | 19.4 | 17.0 | 13.6 | 1.92 | 1.35 / 1.62 |
| Funk / Soul | 39 | 22.6 | 19.4 | 11.6 | 11.5 | 16.3 | 18.6 | 1.96 | 1.37 / 1.69 |
| Pop Rock | 38 | 25.9 | 15.9 | 13.7 | 14.7 | 12.6 | 17.2 | 2.06 | 1.39 / 1.71 |
| **Synth-pop** | 21 | 32.2 | 19.8 | **4.1** | **4.6** | 22.7 | 16.6 | **7.94** | 1.58 / 2.07 |
| Classic Rock | 20 | 24.2 | 19.7 | 10.6 | 11.1 | 17.7 | 16.7 | 2.28 | 1.61 / 2.26 |
| **Country** | 18 | 20.4 | 19.2 | **5.6** | 18.6 | 17.9 | 18.4 | **3.63** | 1.68 / 2.29 |
| **New Wave** | 13 | **49.1** | 11.4 | **2.9** | 7.3 | 21.6 | 7.8 | **17.19** | 1.82 / 2.62 |
| **Hard Rock** | 11 | 32.9 | 24.8 | **3.4** | 10.3 | 20.1 | 8.5 | **9.67** | 2.04 / 3.32 |
| **Disco** | 11 | 20.7 | 14.1 | 7.3 | 6.1 | **35.8** | 16.0 | **5.82** | 2.07 / 3.36 |
| **Ambient** | 10 | **39.2** | 27.8 | 9.6 | **3.5** | 8.2 | 11.7 | **11.34** | 2.18 / 3.69 |

*(22 subsets measured; the full table including Blues, Folk, Fusion, Indie Rock, Psychedelic Rock,
Jazz-Funk, Prog Rock and Folk Rock is in the probe output. Random control = 400 draws of the same
size from the same 321 rows.)*

**Headline: 14 of 22 coherent subsets exceed their own size-matched control's p90.** Median coherent
imbalance 2.21; max 17.19.

### 2.1 The direction is systematic, and it inverts the original defect

The per-head σ ratio (subset σ ÷ global σ) shows what is happening:

| subset | valence | arousal | dance | acoustic | happy | relaxed |
|---|---:|---:|---:|---:|---:|---:|
| Ambient | **1.49** | 1.25 | 0.74 | **0.44** | 0.68 | 0.81 |
| Synth-pop | 1.00 | 0.79 | **0.36** | **0.38** | 0.84 | 0.72 |
| New Wave | 1.31 | 0.63 | **0.31** | 0.50 | 0.87 | 0.52 |
| Hard Rock | 0.78 | 0.67 | **0.25** | 0.43 | 0.61 | 0.39 |
| Electronic | 1.16 | 1.09 | **0.66** | **0.55** | 0.98 | 1.00 |

**Coherent collections compress the musicnn heads and leave the emomusic heads intact.** Under
global σ that means valence and arousal become *dominant* inside such a collection — Ambient 67 %
emomusic, New Wave 60 %, Electronic 48 %, against the 33 % the design intended. **The design would
have inverted the original 97/3 defect rather than removing it, per user, invisibly.**

The owner's exact example is the worst case in the table. That is not luck; it is the mechanism.

### 2.2 The small-n floor — a second finding that constrains every option

The random control is independently informative. Even for a collection that is a *perfectly random
draw* from the library — the most favourable possible case for any fixed σ — realized per-head
imbalance is:

| collection size | imbalance median | p90 |
|---|---:|---:|
| 10 | 2.33 | 3.69 |
| 20 | 1.61 | 2.16 |
| 50 | 1.34 | 1.55 |
| 100 | 1.20 | 1.32 |
| 200 | 1.10 | 1.16 |

**At small collection sizes, per-head influence balance is not controllable by *any* choice of σ.**
A 12-album collection has lumpy realized spread no matter what you divide by. So "equalize per-head
influence" is only a meaningful goal above roughly n = 50, and only comfortably above n = 100. Any
option that computes statistics per user inherits this as a hard floor.

---

## 3. (a) Is per-head standardization still the right mechanism? — No, and here is the precise reason

This is the crux and my earlier explanation was weak. Here is the sharp version.

**Two different defects were conflated under one fix.**

**Defect 1 — a unit artifact.** `essentia_mapper.rb:44` divides emomusic by its **declared** 8-unit
band (`EMOMUSIC_RANGE`, corroborated by `registry.rb:249` `native_range: (1.0..9.0)`) while the
model's realized output occupies roughly 3.2–6.7 — about 3.4 units. musicnn arrives as an already
0..1 softmax probability. So the six heads reach the metric **in different units**, and an
unweighted Euclidean metric silently weights by units. This defect lives in the *mapper and the
model*. It is identical for every user, every collection size, and every future album. It does not
go stale as the catalogue grows; it changes only when the pinned model changes — and that already
has a seam (the gem repin, issue #30).

**Defect 2 — population spread is not uniform.** Even in consistent units, the realized spread of
each head differs, so influence is uneven. **This defect is a property of whichever population you
are ranking over** — and the population being ranked is one user's collection.

**A fixed reference distribution can correct Defect 1. It cannot correct Defect 2 for a set it was
not measured on.** That is the whole objection in one sentence, and it is correct. Dividing by a
global σ inside a user's collection does not equalize anything inside that collection; it just
imposes a different, unchosen, per-user weighting — which §2 measures at up to 17×.

**So: is a fixed reference distribution defensible even though the ranked set is a subset?**
Only for Defect 1, and only if we stop claiming it does Defect 2. **A per-head *unit* constant is
defensible. A per-head *distributional* constant is not.** My design used the same six numbers for
both jobs and inherited the wrong justification for one of them.

---

## 4. (b) The options

Owner premise, unchanged: per-head influence must be **deliberate, reviewable, reproducible**;
0..1 stays for display.

| # | option | deliberate? | reviewable? | reproducible? | equalizes inside the ranked set? | operational cost as catalogue grows |
|---|---|---|---|---|---|---|
| **A** | Frozen global μ/σ *(current design, PR #38)* | ✗ — the numbers are an artifact of one sample | once, then decays | yes | **✗ — §2 measures up to 17×** | **staleness with no fix**; re-measure + `VERSION` bump per drift event, forever |
| **B** | Per-user σ computed at query time, cached | ✓ *rule* is chosen | rule reviewable, numbers not | yes given a fixed collection | **✓ by construction** — but only above the §2.2 floor | cache invalidation per collection change; unusable below ~50 grounded albums; non-local ranking (below) |
| **C** | Global, auto-refreshed on a schedule, value recorded per run | ✗ same as A | worse — numbers move without review | only if you pin the run | ✗ same as A | worst of both: a refresh silently reorders **every** user |
| **D** | Hand-chosen per-head weights, never measured | **✓✓ strongest possible** | **✓✓ six numbers in a PR** | **✓✓ absolutely** | ✗ — and **makes no claim to** | **zero** |
| **E** | **Two-layer: fixed unit normalization + hand-chosen weights** *(recommended)* | **✓✓** | **✓✓** | **✓✓** | ✗ — and says so out loud | **zero** |

### 4.1 Where my earlier frozen-constants argument survives, and where it does not

Baton asked me to test it, not defend it.

- **Determinism / testability — survives, but weaker than I claimed.** I argued per-user statistics
  make results irreproducible. But *recommendations already depend on collection state* — the
  candidate set **is** the collection (`candidate_retrieval.rb:34`). Determinism given a fixed
  collection is preserved under option B. I over-claimed this.
- **Non-local ranking — survives, and it is the strongest one, but it is narrower than I said.**
  Importing one album into an n-album collection moves σ by O(1/n). At n = 200 that is ~0.5 % and
  ranking barely moves; at n = 12 it is large. So non-locality is an argument for a **minimum
  collection size floor**, not against per-user statistics wholesale. I over-weighted it.
- **Reviewability — survives, and it is the one the recommendation rests on.** But it argues
  *against* option A, not for it: a measured table is reviewable exactly once and then rots. **Six
  hand-written numbers are strictly more reviewable than six measured ones**, because there is no
  measurement to go stale, to be mislabelled, or to be re-derived under pressure.
- **Baton's self-criticism is correct.** A drift gate *detects*; it does not *fix*. Presenting a
  detector as the answer to continuous growth was the error. The correct response to "staleness is
  not an option" is **to have nothing that can go stale**, which is what option E delivers.

---

## 5. Recommendation — option E, two layers, zero catalogue statistics

### Layer 1 — unit normalization (fixed; a property of the model, not of any catalogue)

Rescale emomusic by a **reviewed band with margin** instead of its declared 1..9 band, so all six
heads reach the metric in comparable units. This is a one-line change in the mapper's meaning, and
it is the only empirical input in the whole design.

Measured effect on per-head influence over the 321 rows:

| band used for emomusic | valence | arousal | dance | acoustic | relaxed | happy | emomusic total | imbalance |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| declared 1..9 *(today)* | 0.9 % | 1.9 % | 28.2 % | 25.9 % | 24.8 % | 18.2 % | **2.8 %** | **31.9×** |
| conservative 3.0..7.0 | 3.3 % | 7.0 % | 26.1 % | 23.9 % | 22.9 % | 16.8 % | 10.3 % | 7.9× |
| tight realized ≈3.2..6.7 | 7.0 % | 8.8 % | 24.5 % | 22.5 % | 21.5 % | 15.8 % | 15.8 % | 3.5× |

**Layer 1 alone takes the accidental weighting from 32× to between 8× and 3.5×, with no
distributional statistic anywhere.** The band is a *range* of a model's output — one-dimensional,
robust, and reviewable as a single decision — not a per-head distribution over a population. Choosing
the band **is** the deliberate decision; I recommend the conservative end plus the existing clamp,
and recording the realized measurement next to it as the evidence rather than as the value.

**Honest caveat, stated out loud:** the realized band was measured on the same single-user library
as everything else. It is a far weaker dependence than μ/σ (a range, not a distribution) and
widening it with margin makes it weaker still — but it is not zero, and it is the one number in
this design that a second real collection could move.

### Layer 2 — product weights (hand-chosen, never measured)

An explicit six-number table in `d² = Σ wₕ (aₕ − qₕ)²`, saying how much each head *should* matter.
Default: **all equal**. The owner changes them in a PR when the product should change. No
measurement, no drift, no version, no gate.

### 5.1 What this buys — the reason to prefer it over per-user σ

- **No staleness.** Nothing in the recommendation path is a catalogue statistic. Catalogue growth
  changes nothing. The owner's premise is satisfied structurally rather than operationally.
- **No per-user problem.** Works identically for a 12-album collection and a 12,000-album one.
- **No n = 1 generalization problem.** See §7 — this is the strongest argument.
- **Three pieces of machinery disappear.** With coordinates back in 0..1 and fixed weights,
  `MAX_DISTANCE` **returns** as `sqrt(Σ wₕ)` — a genuine finite maximum. `REFERENCE_DISTANCE` and
  the squash are **no longer needed**. And Layer 1 makes album coordinates span ~0..1 on the
  emomusic heads, so an LLM emitting `arousal: 0.9` is reachable — **which dissolves the entire
  motivation for the probit bridge.** The two sides genuinely share a space for the first time,
  rather than being forced into one.
- **Finding B (r(arousal, mood_relaxed) = −0.901) becomes an explicit weight decision** rather than
  a declared-but-unfixed limitation: the owner can simply down-weight one of the two.

### 5.2 The honest limitation, which must be written into the design doc

**Realized per-head influence will still vary by collection, and we are choosing not to control
it.** §2 quantifies how much: up to 17× in a strongly coherent subset. We are accepting that in
exchange for a weighting that is chosen by a person, stable forever, and identical for every user.

**The trade in one line: 3.5×–8× imbalance that a human chose, versus 1× measured on one person's
library and decaying from the day it ships.** Full parity in every collection is only achievable
with per-collection statistics, and those are unmeasurable, unstable below n≈50, and untestable
against a second user today.

### 5.3 If per-collection parity is later wanted (option B, deferred)

It is defensible, but only with the floor §2.2 measured: **compute per-user σ only when the
collection has ≥ 100 grounded albums** (imbalance p90 1.32 at 100, versus 3.69 at 10), and fall
back to the Layer 1+2 fixed weights below that. That is a concrete, measured threshold rather than
a guess. Do not build it now — build it when there is data to justify it (§6).

---

## 6. (c revised) What it would take to answer the question we cannot answer

**The question:** do real user collections' per-head spreads track each other closely enough that
any single fixed table is appropriate for all of them?

**What would answer it:** per-head σ and the §2 influence-share computation across **≥ 20 real
collections of ≥ 50 grounded albums each**, from production. That is the only thing that answers
it. No amount of subsetting one library substitutes, because subsets of one person's taste are not
samples of other people's taste.

**Where it comes from:** production, after real users import Discogs collections. Today production
has no such data — this database has exactly one collection.

**What to do in the meantime, and I recommend this strongly:** **instrument it.** At scoring time
the candidate set is already in memory. Computing each head's realized share of mood distance
across that set is a few arithmetic operations, and `RecommendationEvent` already persists
per-query diagnostics (`pipeline.rb:38-48`). Adding a `mood_head_shares` payload turns an
unanswerable design question into an **observable production metric within days of launch**, at
near-zero cost, with no schema risk beyond one additive column.

Then the deferred option B decision gets made on data instead of on argument — and if the shares
turn out to be stable across users, the case for a fixed table becomes an evidence-backed one
rather than the assumption it is today.

**A design that only works if per-user distributions track the global one, when we cannot check
that, must say so out loud.** Option E's answer is better than saying so: **it does not require
that assumption at all.** That is its main argument.

---

## 7. How much survives the n = 1 sample — including the finding that started the ticket

Baton is right that every number on this ticket comes from one person's library. Taking that
seriously:

| artifact | survives? |
|---|---|
| **The 97/3 finding itself** | **Yes — because its cause is in the code, not in the data.** I derived it independently from `essentia_mapper.rb:44` (divide by the declared 8-unit band) and `registry.rb:241-273` (emomusic `native_range` 1..9 vs musicnn `range_kind: :hard` 0..1). For emomusic to reach parity by accident, a library's emomusic output would have to span ~6 of its 8 declared units; the models concentrate output mid-scale by construction. **The defect is a property of the mapper and the models. The 97.21/2.79 split is a measurement of its size on one library; the defect's existence does not depend on that library.** |
| 97.21 % / 2.79 %, 31.9× | n = 1. Directionally sound, magnitude unverified. Do not quote as a population fact. |
| `MU`, `SIGMA` (all six each) | n = 1. **Eliminated under option E.** |
| `REFERENCE_DISTANCE` = 3.0217250259 | n = 1. **Eliminated** (no squash). |
| `MOOD_VECTOR_WEIGHT` = 0.24 | n = 1 **and** tied to z-space + squash. **Rework.** |
| Finding B correlations (−0.9014, +0.7146) | n = 1, but a model-family property (arousal and "relaxed" are near-antonyms by construction). Survives as a design consideration; becomes a Layer 2 weight decision. |
| The dispersion-vs-mean calibration insight (my step-4 §2) | **Survives fully — it is metric-agnostic.** Ranking depends on within-query dispersion, not on the mean, under *any* weighting scheme. |
| The emomusic realized band (3.2–6.7) | n = 1, and it is **the one empirical input option E retains**. Mitigated by margin; flagged in §5. |

**Note the shape of that table: the recommended design depends on essentially none of the
single-user measurements.** That is not a coincidence — it is why I am recommending it.

---

## 8. Finding: the constants are mislabelled (endorsing Baton's point 2)

`app/models/mood_vectors/catalogue_scale.rb` lines 5–8 read
*"Measured on vibe_doctor_development … n = 321 … Row filter: mood_source LIKE 'essentia%'"*
under a class named **CatalogueScale**, which reads as a catalogue-level population sample.

It is **one user's personal collection** — and in this database it happens to be *every* grounded
row, which is exactly what makes the mislabelling invisible. `SAMPLE_SIZE = 321` implies a sample
of a larger population; there is no larger population, and n = 1 in the dimension that matters
(users). The `NOTE: production representativeness is unverified` line is true but far too weak: the
issue is not production representativeness, it is that the sample has **one member of the
population the name implies**.

**This is a finding in its own right regardless of the design outcome.** If any part of the table
survives in any form, the provenance comment must say "measured over a single user collection
(user_id 3), n_users = 1" and the class must not be named for a population it does not sample.

---

## 9. (d) The in-flight work — what survives, what is rework, and whether to stop Rivet

**Recommendation: let sub-steps 1–2 finish. Stop sub-steps 3–4 now.** They are building directly on
the invalidated premise and every hour spent is rework.

| work item | status |
|---|---|
| **Sub-step 1 — §4.3 doc correction** | **KEEP, let it finish.** The dispersion-vs-mean insight is metric-agnostic and correct under any weighting. It is the one piece of this ticket that gets more valuable, not less. |
| **Sub-step 2 — fixtures + calibration gate** | **KEEP the mechanism, discard the number.** A frozen row corpus + frozen queries + a dispersion-ratio gate is exactly the right shape and is reusable verbatim against Layer 1+2. Two required changes: the fixture must be **relabelled** as one user's collection (§8), and the `0.24` expected value is rework. Let it finish, then re-baseline. |
| **Sub-step 3 — `QueryProjection` (probit bridge)** | **STOP.** Its motivation was that albums and the LLM occupy different spaces. **Layer 1 dissolves that** by making album coordinates span ~0..1 on the emomusic heads. The code is not wrong — it is clean, machine-precision, and well-tested — it is *unneeded*. Shelve it; it returns only if option B (§5.3) is ever built. |
| **Sub-step 4 — `StandardizedDistance`** | **STOP.** The z-projection is catalogue-dependent and goes away. The *weighted-Euclidean + bounded normalizer* shape survives and is strictly simpler — no μ, no squash, `MAX_DISTANCE` returns as `sqrt(Σ wₕ)`. |
| **PR #38 (frozen table)** | **Do not merge as-is.** Under option E, `CatalogueScale` is not needed in the recommendation path. If any of it is retained as *evidence* (the measurement, the correlations), it belongs in `docs/superpowers/specs/`, relabelled per §8 — not as a constant the scoring path reads. |
| **Baton's instinct** | **Correct on the distance mechanism, wrong on the probit bridge.** The distance mechanism is reusable regardless of where the numbers come from. The probit bridge is not merely re-pointable — Layer 1 removes the problem it existed to solve. |

---

## 10. Things I now think are bad ideas — including two more of my own

1. **`CatalogueScale` as a recommendation-path constant.** §3. Corrects a unit defect and a
   distributional defect with the same six numbers, and is only entitled to the first.
2. **The drift gate as an answer to staleness.** It is a detector. On a continuously growing
   catalogue, "gate fires → human re-measures → PR bumps VERSION" is unbounded operational burden.
   Baton identified this before I did and is right.
3. **My step-4 probit bridge recommendation.** §9. Technically sound, machine-precision, and
   solving a problem that Layer 1 removes. Two reviews ago I argued for it; it should not ship.
4. **Auto-refreshing global statistics on a schedule (option C).** A refresh silently reorders every
   user's recommendations with no review and no commit. Strictly worse than either neighbour.
5. **Per-user σ without a minimum-collection-size floor.** §2.2 measures the floor: at n = 10 even a
   random collection shows 2.33× median imbalance. Dividing by a σ estimated from 10 albums
   amplifies noise rather than removing it.
6. **Reporting any divergence number from this database.** §1. The two sets are the same rows.
7. **Leaving `SAMPLE_SIZE = 321` under a class called `CatalogueScale`.** §8. It implies a
   population sample where n_users = 1.

---

## 12. (b) The decision threshold — pre-registered, before the numbers exist

Naming this after seeing the data is how a measurement gets rationalised. So, in advance:

### 12.1 The right quantity to threshold

Not σ divergence for its own sake. The decision-relevant quantity is **the realized per-head
influence imbalance inside each user's collection, computed under the frozen global σ** — the
§2 table, per real user:

```
share_h(u)  ∝  Var_u(v_h) / σ_global_h²          imbalance(u) = max_h share_h(u) / min_h share_h(u)
```

### 12.2 The anchor — and why it is not arbitrary

The threshold is a **comparison against the alternative**, not an aesthetic judgement. Layer 1
alone — statistics-free, no staleness, no per-user problem — delivers an imbalance of **3.5×
(tight band) to 7.9× (conservative band)** on the data I have (§5, Layer 1 table).

**A frozen global table has to beat the statistics-free option to justify its existence.** If it
does not, we are paying staleness, a re-measurement cadence, a `VERSION`, a drift gate, and a
provenance liability for balance we could have had for free.

### 12.3 The numbers

| outcome | condition on `imbalance(u)` across real users | decision |
|---|---|---|
| **PASS** | median ≤ **2.0** *and* p90 ≤ **3.0** *and* max ≤ **4.0** | frozen global σ is *defensible* — but see §13.1; it still does not answer the growth limb |
| **AMBIGUOUS** | anything between | **defaults to FAIL** — tie goes to the design with no operational burden |
| **FAIL** | median > **2.0** *or* p90 > **3.5** *or* any user > **6.0** | frozen global σ is **unacceptable**; it delivers no more balance than Layer 1 while carrying all of Layer 1's costs plus staleness |

Secondary diagnostic, per head: **σ_u,h / σ_global,h outside [0.70, 1.40] for the median user**
counts as divergence. Calibration for that band from §2.1: whole-library-like subsets (Rock n=201,
Pop n=57, Indie Rock n=54) sit at 0.89–1.05; coherent subsets fall to 0.25–0.44 on danceability and
mood_acoustic. The band discriminates cleanly between those two regimes.

### 12.4 Validity preconditions — a PASS is only meaningful if these hold

State these now, because a PASS obtained from two near-identical collections is the same
"zero deviation is a reading, not a verdict" error at a larger scale:

1. **≥ 2 collections, each with ≥ 50 grounded albums.** Below that the per-user σ estimate is too
   noisy for the comparison to mean anything (§14).
2. **Jaccard overlap between any two compared collections < 0.5.** Baton's query already includes
   the overlap check — this is what it is for. If the collections are largely the same albums, the
   result is **INCONCLUSIVE, not PASS.**
3. **The per-user emomusic raw min/max must be reported** (see §15.3 — it is the falsifier for the
   finding that started this ticket, and it also sets Layer 1's band).

If any precondition fails: **INCONCLUSIVE → treat as FAIL**, for the same reason ambiguity does.

---

## 13. (a) Both branches

**The headline: option E is the recommendation under every branch.** What the branches change is
the *follow-up* and the *confidence*, not the decision. One branch does open a genuinely better
long-term answer — §13.3.

### 13.1 Branch PASS — per-user distributions track the global one

**Recommendation: still option E.** A PASS removes one limb of the owner's objection (wrong
population) and **leaves the other limb untouched**: *"expect it to grow and staleness is not an
option."* A frozen table measured today is still stale tomorrow, on a catalogue that grows
continuously, whether or not it currently fits every user.

But a PASS does something valuable that is worth stating: **it makes the measurement a legitimate
*informant* for the Layer 2 weights.** The owner can look at the measured σ ratios when hand-choosing
the six numbers — using the evidence *once, in a human decision*, rather than letting the code read
a live table that decays. That is the correct way to spend a PASS.

**Cost of this branch: ~zero.** Layer 1 + hand-chosen weights, informed by data we now trust more.
Do not build option B.

### 13.2 Branch FAIL + small collections (median grounded < 100)

**Recommendation: option E, and per-user σ is ruled out too.** This is the important asymmetry:
divergence means each user *needs* their own σ, while small collections mean each user *cannot have
a usable one* (§14). Both roads are closed; E is the only viable design.

**Cost: the declared limitation in §5.2 becomes materially larger and must be written more
loudly** — per-head influence genuinely does vary a lot per user, we know it, and we are choosing
not to control it because controlling it is not possible with the data available. That is an honest
position; it is not a comfortable one, and the owner should see it plainly.

### 13.3 Branch FAIL + large collections (median grounded ≥ 100)

**This is the only branch where my recommendation changes materially.** Divergence is real *and*
estimable. Here **option B (per-user σ computed at query time) genuinely delivers something E
cannot**: equal per-head influence inside each user's actual ranked set, by construction.

**Recommendation: ship E now, then build B as an enhancement** with the §14 floor and E as the
fallback beneath it. Do not skip E and jump to B: the cold-start hole (§14.2) means the fallback
path must be built and maintained anyway, so E is not throwaway work under any branch.

**Cost: two scoring paths, permanently** — plus per-user cache invalidation on collection change,
plus the non-local ranking property (§4.1) above the floor. Justified only by a measured FAIL, never
in advance.

### 13.4 Decision table

| | median grounded < 100 | median grounded ≥ 100 |
|---|---|---|
| **PASS** | **E**, weights informed by the measurement | **E**, weights informed by the measurement |
| **FAIL / INCONCLUSIVE** | **E only** — B not buildable; declare the limitation loudly | **E now, B later** — the one branch where B is warranted |

---

## 14. (c) Collection size — an independent constraint that may settle it alone

Baton is right that this can rule out per-user statistics **regardless of the divergence answer**,
and I have measured the floor rather than guessed it.

### 14.1 The floor, from §2.2's size-matched random control

| n grounded | control imbalance median / p90 | σ relative standard error ≈ 1/√(2n) | resulting influence error (1/σ² amplifies) |
|---:|---|---:|---:|
| 10 | 2.33 / 3.69 | 22.4 % | ~58 % |
| 20 | 1.61 / 2.16 | 15.8 % | ~39 % |
| 30 | — | 12.9 % | ~31 % |
| **50** | 1.34 / 1.55 | **10.0 %** | **~21 %** |
| **100** | 1.20 / 1.32 | **7.1 %** | **~15 %** |
| 200 | 1.10 / 1.16 | 5.0 % | ~10 % |

The amplification matters and is easy to miss: **you divide by the estimated σ**, so a head whose σ
is under-estimated by 20 % has its influence inflated by 1/0.8² = **56 %**. Noise in σ does not
average out — it is squared and inverted.

**Recommendation: minimum n = 100 grounded albums for per-user σ. Hard floor 50. Below 50, fixed
weights, no exceptions.** At n = 10 — a plausible size for a new user — the control p90 imbalance is
3.69, i.e. *worse than the statistics-free Layer 1 option delivers*. Per-user σ on a small
collection is not a refinement; it is noise dressed as precision.

### 14.2 The cold-start hole — an argument that stands on its own

σ requires *grounded* rows, and grounding requires `EnrichAlbumJob` to have run
(`enrich_album_job.rb:23-26`). **A user who imports 300 albums has zero grounded albums until
enrichment completes.** During that window per-user σ does not exist at all — not "is noisy",
*does not exist*.

Therefore **the fixed-weight fallback path must be built and maintained under every branch,
including branch 13.3.** Option B is never a replacement for E; it is at best a layer on top of it,
for a subset of users, some of the time. That is a permanent two-path complexity cost, and it is a
strong independent reason to ship E first and treat B as an evidence-gated enhancement rather than
a design goal.

### 14.3 What Baton's production query should also report

Beyond the divergence stats, three numbers decide §13's branch and §15's falsifier:

1. **Grounded-album count per collection** (not total items — grounded), for the §14.1 floor.
2. **Jaccard overlap between collections**, for the §12.4 validity precondition.
3. **Per-user emomusic raw min / max** (i.e. `valence·8+1`, `arousal·8+1`), for §15.3 and for
   choosing Layer 1's band with real margin.

---

## 15. (d) Does the 97/3 finding generalize? — arguing it, not assuming it

Baton is right to reopen this: the split was measured on one collection. Here is the argument, and
it does **not** rest on that measurement.

### 15.1 What would have to be true for the finding to be an artifact

The stored value is `(raw − 1)/8`, so `σ_stored = σ_raw / 8`. musicnn heads measure σ_stored ≈
0.27–0.33. For emomusic to reach parity in *any* library, that library would need
`σ_raw ≈ 2.2–2.7` on the 1..9 scale — meaning ±2.5σ spans roughly the entire declared band, with
emomusic predictions routinely landing near 1 and near 9.

So the question is not "was 321 albums enough?" It is: **does the emoMusic head ever produce
near-full-scale predictions?** That is a property of the model, not of the music.

### 15.2 Two reasons from the code and the model architectures — neither from this library

1. **The gem's own registry says the 1..9 band is not an output bound.** `registry.rb:249-251`
   declares emomusic `native_range: (1.0..9.0)` with `range_kind: :nominal` and
   `sanity_range: (-3.0..13.0)`. The author deliberately set the enforced band 2× wider on each
   side, because 1..9 is the *annotation* scale the model was trained against, not a range the
   model's output occupies. A regression head fitted to mid-concentrated Likert annotations
   produces mid-concentrated predictions — regression to the mean is the defining behaviour of a
   least-squares regressor, not an accident of this catalogue.
2. **The asymmetry is architectural.** The four musicnn heads are *softmax classifiers* over binary
   classes (`registry.rb:266-268`, `range_kind: :hard`, `0.0..1.0`), and my global measurement
   confirms they saturate: min 0.000, max 1.000 on all four. **Classifiers spread toward the
   endpoints; regressors shrink toward the mean.** Putting a saturating classifier and a shrinking
   regressor into one unweighted Euclidean metric under-weights the regressor *by construction*,
   in any library.

**Conclusion: what generalizes is the mechanism and its approximate size — emomusic is
under-weighted by roughly `(8 / realized_raw_span)²`, and `realized_raw_span` will be materially
less than 8 for any library, because a Likert-scale regressor does not emit full-scale
predictions.** The precise figures 97.21 / 2.79 and 31.9× are n = 1 and should never be quoted as
population facts. The *defect* is in `essentia_mapper.rb:44` and in the model types; the
*measurement* is of its size on one library.

### 15.3 The falsification condition — pre-registered, testable by the query already written

I will not assert this without a falsifier:

> **The 97/3 finding is falsified if any real user collection shows an emomusic raw span > 6.0
> units** (against the 3.4 observed here). A span of 6 would put emomusic within ~1.8× of the
> musicnn heads, at which point the imbalance is a design preference rather than an accident and
> Layer 1's band correction is unnecessary.

Baton's production query should report per-user emomusic raw min/max (§14.3.3). **If any user
exceeds a 6.0 span, bring this back to me — Layer 1's premise, not just its band, needs
rethinking.** If all users sit near 3–4, the finding is confirmed on independent populations and
Layer 1's band can be chosen with real margin rather than from a single sample.

---

## 16. Summary

- **The owner is right.** Global σ does not equalize per-head influence inside the set that is
  actually ranked, and the residual imbalance varies per user, invisibly.
- **Measured with a size-matched random control:** 14 of 22 coherent subsets exceed their control's
  p90. Electronic at n = 61 — where small-n noise is not an available explanation — reaches
  **4.47× against a control p90 of 1.48×**. Ambient 11.3×, New Wave 17.2×. Coherent collections
  compress the musicnn heads and leave emomusic intact, **inverting** the original defect.
- **Per-user divergence is unmeasurable here** (one collection, identical to the whole grounded
  pool). Not computed, not estimated, not reported as reassurance.
- **Recommendation: option E.** Layer 1 = fixed emomusic band correction (a model property; takes
  the accidental weighting from 32× to 3.5–8×). Layer 2 = hand-chosen per-head weights, never
  measured. **Zero catalogue statistics in the recommendation path**, so nothing can go stale, vary
  per user, or depend on the n = 1 sample. `MAX_DISTANCE` returns; `REFERENCE_DISTANCE`, the squash,
  and the probit bridge all disappear.
- **Stated out loud:** realized per-head influence will still vary by collection and we are choosing
  not to control it. The trade is a chosen 3.5–8× against a measured 1× that decays from day one.
- **Instrument `RecommendationEvent` with per-head realized shares** so the unanswerable question
  becomes an observable production metric, and option B (per-user σ, floor n ≥ 100) can later be
  decided on evidence.
- **Rivet: let sub-steps 1–2 finish, stop 3–4 now. PR #38 should not merge as-is.**

Added after the second correction (production has ≥ 2 collections):

- **Pre-registered threshold (§12), named before the data exists.** Quantity: per-user influence
  imbalance under frozen global σ. **PASS** = median ≤ 2.0, p90 ≤ 3.0, max ≤ 4.0. **FAIL** =
  median > 2.0, p90 > 3.5, or any user > 6.0. **Ambiguous defaults to FAIL.** The anchor is not
  aesthetic: Layer 1 delivers 3.5–7.9× for free, so a frozen table that cannot beat that has no
  reason to exist. Validity preconditions: ≥ 2 collections, ≥ 50 grounded each, Jaccard overlap
  < 0.5 — otherwise **INCONCLUSIVE, which is treated as FAIL**, because a PASS from two
  near-identical collections is the same error one scale up.
- **Both branches (§13): option E is the recommendation under every outcome.** A PASS does not
  answer the *growth* limb of the owner's objection, so frozen constants still lose; what a PASS
  buys is the right to use the measurement as a one-time human *informant* for the hand-chosen
  weights. **The single branch that changes my answer is FAIL + median collection ≥ 100 grounded**
  — there, per-user σ genuinely beats E and should be built as an evidence-gated enhancement on top
  of E, never instead of it.
- **Collection size may settle it alone (§14).** Minimum **n = 100** grounded for per-user σ, hard
  floor 50, fixed weights below. Noise in σ is *squared and inverted* — a 20 % σ under-estimate
  inflates that head's influence by 56 %. And the **cold-start hole is decisive on its own**: a user
  who imports 300 albums has *zero* grounded rows until enrichment runs, so per-user σ does not
  exist at all. **The fixed-weight path must therefore be built and maintained under every branch**
  — which is why E is never throwaway work.
- **The 97/3 finding generalizes, and I argue it rather than assume it (§15).** The mechanism is in
  the code and the model architectures, not in the data: `essentia_mapper.rb:44` divides by a
  declared band that `registry.rb:249-251` explicitly marks `:nominal` with a 2×-wider enforced
  band, and the metric mixes **saturating softmax classifiers with a shrinking Likert regressor** —
  classifiers spread, regressors shrink, in any library. What generalizes is
  `(8 / realized_raw_span)²`; the figures 97.21/2.79 and 31.9× are n = 1 and must not be quoted as
  population facts. **Falsifier, pre-registered: any real collection with an emomusic raw span
  > 6.0 units falsifies it** — bring that back to me, because Layer 1's premise and not just its
  band would need rethinking.
- **Three additions requested for Baton's production query (§14.3):** grounded-album count per
  collection (not total items), Jaccard overlap between collections, and per-user emomusic raw
  min/max. Those three decide the branch, the validity precondition, and the falsifier respectively.
  **I have not run it and am not asking to.**
