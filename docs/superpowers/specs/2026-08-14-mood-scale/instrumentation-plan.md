# INSTRUMENTATION — `mood_head_shares` — Principal plan (Tier 1 gate)

**Author:** Keystone (Principal Engineer) · **Date:** 2026-09-20
**Basis:** `feat/mood-scale-option-e` @ `bc6bc5d` · owner approval 2026-09-20
**PLAN ONLY. No code, no migration, no commits.**

Builds on the sizing already given; that is not repeated. Everything below is traced against the
code as it exists at `bc6bc5d` — where I say a method or a stub exists, I opened it.

---

## 1. Branching and landing order

Branch **`feat/mood-scale-instrumentation`** off **`feat/mood-scale-option-e` @ `bc6bc5d`** — not
off `main`. It depends on `MoodVectors::MoodDistance` and `MoodVectors::HeadWeights`, neither of
which exists on `main`.

**One commit, one PR, stacked with base = `feat/mood-scale-option-e`.**

**Landing order, and it is not negotiable:**

1. Option E's PR merges to `main` first.
2. The instrumentation PR is then retargeted/rebased onto `main` and merged second.

**Never merge the instrumentation branch into `feat/mood-scale-option-e`.** That would put a
migration inside Option E's revert unit and destroy the property the whole stack exists to protect:
Option E's rollback is a single revert of the wiring commit, with no schema to unwind. If Option E
is reverted before this lands, this branch is dropped or rebased — never the reverse.

---

## 2. The migration

```
add_column :recommendation_events, :mood_head_shares, :jsonb, default: {}, null: false
```

One file, one statement, no backfill, no index.

- **Reversible: yes, automatically.** `add_column` with an explicit type is reversible by Rails, so
  a plain `def change` is correct — no `up`/`down` pair, no `reversible` block.
- **Named rollback:** `bin/rails db:rollback STEP=1` drops the column. Everything written is
  diagnostic; nothing in the app reads it (§4), so dropping it cannot break a code path. The data
  loss on rollback is total and acceptable.
- **No table rewrite.** Postgres 11+ stores a non-volatile column default in the catalogue rather
  than rewriting rows, so `default: {}, null: false` on an existing table is a metadata-only
  operation. No long lock. `recommendation_events` is one row per recommendation, so it is small
  regardless.
- **No index.** Nothing queries this column yet. A GIN index would be speculative — add one when
  there is a query, not before.
- **No backfill.** Pre-existing rows keep the `{}` default, which is exactly the "never
  instrumented" state the contract needs (§3).

---

## 3. The column contract

### 3.1 Shape — and I am overriding my own §6 here

`principal-optionE.md` §6 says "six keys" and then also says the column records the max observed
mood term, which is a seventh value. **That is an inconsistency in my own plan and this is the fix.**
Rather than eight flat keys mixing measurements with metadata, the column is **three top-level
keys**:

```jsonc
{
  "shares": {                    // object, exactly the six MoodVector::MOOD_HEADS keys
    "valence":       0.0326,     // float, 0.0..1.0
    "arousal":       0.0704,
    "danceability":  0.2607,
    "mood_acoustic": 0.2393,
    "mood_relaxed":  0.2287,
    "mood_happy":    0.1682
  },
  "max_term":     0.7431,        // float, >= 0.0; nominal bound 1.0, hard bound 1.1902380714
  "scored_count": 317            // integer, >= 1
}
```

Nesting the six under `shares` keeps the data/metadata boundary explicit and makes the object
self-describing to whoever reads it in six months. It also means a later addition (§3.4) is purely
additive at the top level and cannot be mistaken for a head.

### 3.2 Key by key

| key | type | range | meaning |
|---|---|---|---|
| `shares.<head>` | float | `0.0 .. 1.0` | that head's fraction of total weighted squared mood distance across the scored candidate set. The six sum to `1.0` (§5). Keys are exactly `MoodVector::MOOD_HEADS`, **by name** — never positional. |
| `max_term` | float | `>= 0.0` | the largest `MoodDistance.term` observed across the scored set. Nominally `<= 1.0`; `1.1902380714` is the hard bound the deliberate no-clamp design permits (pinned by G15). This is how §1.4's nominal bound is *monitored* rather than assumed. |
| `scored_count` | integer | `>= 1` | how many candidates the shares were computed over. **This is the data's own non-vacuity floor** — shares over 3 albums and shares over 300 are not the same evidence, and nothing else on the row records it (§3.3). |

### 3.3 `scored_count` is not `candidates_considered` — do not conflate them

`recommendation_events.candidates_considered` is written at `pipeline.rb:26` as `admitted.size` —
the count **after** `GenreAdmissionFilter`. `scored_count` is the count **before** it, over every
`candidate_id` that `CandidateRetrieval` scored. They cover different sets and will routinely
differ. Both are correct for their own question; a later analyst who assumes they match will draw a
wrong conclusion. This must be stated in the migration comment, not only here.

### 3.4 The empty and null cases — explicitly

| state | stored value | how it arises |
|---|---|---|
| **never instrumented** | `{}` | pre-migration rows, and any future code path that writes an event without a retrieval. Distinguishable from every real value by the absence of `scored_count`. |
| **instrumented, real data** | all three keys, `scored_count >= 1` | the normal path |
| **zero scored candidates** | **unreachable** | `CandidateRetrieval#call:21` returns `[]` when `candidate_ids` is empty, and `pipeline.rb:20` raises `NoCandidatesError` when `admitted` is empty. `persist_event` is therefore never reached with zero candidates. `scored_count == 0` must never appear; **G20 asserts it cannot**, so if it ever does, something upstream changed. |
| **total squared distance is 0** | six `0.0` shares, `scored_count >= 1` | arithmetically reachable (a single candidate whose calibrated coordinates equal the query exactly). Normalising would divide by zero. Contract: write six zeros. The shares then do **not** sum to 1.0, and that is the signal — it is unambiguous because `scored_count >= 1` distinguishes it from `{}`. |
| **album has no mood vector** | **cannot be recorded — the request raises first** | see §3.5 |

### 3.5 No mood vector at all — traced, and it is a pre-existing Option E finding

The brief asks what the column holds when there is no mood vector. **Traced: nothing, because the
pipeline dies before the write.**

`album.rb:15` declares `has_one :mood_vector` with no presence guarantee and no DB constraint.
`candidate_retrieval.rb:44` passes `album.mood_vector` straight into `MoodDistance.term`, which
calls `HeadCalibration.album_coordinate(album_mood, head)` → `mood_vector.public_send(head)` →
**`NoMethodError` on `nil`**. Candidates come from `Embedding.nearest_neighbors`
(`candidate_retrieval.rb:35`) with **no `Album.grounded` filter** — unlike
`Albums::VibeMapBuilder`, which does apply one. In the normal flow `EnrichAlbumJob` writes the mood
vector (`:25-26`) before the embedding (`:40-42`), so an embedded album has one; but that is an
ordering habit, not an invariant, and `dependent: :destroy` on the mood vector leaves the embedding
behind.

**This is a pre-existing exposure in Option E's wiring commit, not something this ticket
introduces, and this ticket must not fix it** — Option E is under final review and widening its diff
is the wrong trade. **Raise it separately against Option E's review.** Design consequence here: the
contract does not pretend to handle the case, and if Option E later adds a guard, the contract gains
an additive fourth top-level key (`skipped_no_mood_count`) without disturbing anything above.

---

## 4. The call chain, as it actually exists at `bc6bc5d`

Traced line by line. Nothing below is assumed.

```
Pipeline#call                                      pipeline.rb:16
  :17  understanding = QueryUnderstandingCache.fetch(@query_text)
  :18  CandidateRetrieval.new(understanding, album_ids: user_album_ids).call   <-- instance discarded inline
         CandidateRetrieval#call                   candidate_retrieval.rb:18
           :19  maps = facet_distance_maps
           :20  candidate_ids = maps.values.flat_map(&:keys).uniq              <-- THE SCORED SET
           :21  return [] if candidate_ids.empty?
           :23  albums = Album.where(id: candidate_ids).includes(:mood_vector)
           :25-28  candidate_ids.map { blended_score(...) }.sort_by.first(@limit)
                     blended_score                 candidate_retrieval.rb:41
                       :43  MoodVectors::MoodDistance.term(album_mood:, query_mood:)
                              MoodDistance.term    mood_distance.rb:4
                                sums HeadWeights.for(head) * delta**2 over MOOD_HEADS,
                                then sqrt / HeadWeights.max_distance
  :19  GenreAdmissionFilter.new(candidates, ...).call
  :20  raise NoCandidatesError if admitted.empty?
  :26  persist_event(...)                          pipeline.rb:38
         :41  RecommendationEvent.create!(...)
```

### 4.1 One computation, two consumers — the single most important design point

**`MoodDistance.term` already computes the six per-head weighted squared deltas and throws them
away** (`mood_distance.rb:5-11`). If the instrumentation recomputes them independently, there are
two implementations of the same arithmetic that can silently drift — and the existing G6/G7/G14
gates would then be validating one path while production scores on the other. That is precisely the
failure this ticket has shipped repeatedly.

**Therefore: one computation.** Add `MoodVectors::MoodDistance.breakdown(album_mood:, query_mood:)`
returning a small immutable value object carrying the per-head weighted squared deltas **keyed by
head name** and the derived `term`, and **reimplement `.term` as `breakdown(...).term`**. `.term`'s
public behaviour is then preserved by construction, and G16 pins the invariant rather than trusting
it.

### 4.2 Accumulation and threading

**Accumulate in `CandidateRetrieval#blended_score`** (`:41`), which already runs once per scored
candidate, over **all** of `candidate_ids` — not the `.first(@limit)` slice (`:28`) and not the
post-`GenreAdmissionFilter` set. Three instance accumulators: per-head squared totals (a hash keyed
by head), the running max term, and the scored count.

Expose a memoised `#head_shares` reader that normalises (§5) and returns the §3.1 object. It must be
safe to call after `#call` and must not recompute anything.

**Thread by retaining the instance**, per the standing ruling:

```
# pipeline.rb:18
retrieval  = CandidateRetrieval.new(understanding, album_ids: user_album_ids)
candidates = retrieval.call
...
# pipeline.rb:26 / :38
persist_event(..., head_shares: retrieval.head_shares)
```

`CandidateRetrieval#call` keeps returning a bare `Array` of `Candidate`, so
`GenreAdmissionFilter`, `RankedCandidate.rank`, `RerankClient` and `TemperatureSampler` are all
untouched.

### 4.3 Blast radius I traced that the sizing did not name

**`spec/models/recommendations/pipeline_spec.rb` stubs `CandidateRetrieval` with a *verifying*
`instance_double` at three sites — `:19-20`, `:51-52`, and `:65`.** An `instance_double` raises on
any message it was not stubbed with, so the moment `Pipeline` calls `retrieval.head_shares`, **all
three specs fail**. Each must gain `head_shares:` in its stub, with a value matching the §3.1 shape.
This is not optional cleanup; it is part of the change.

---

## 5. Normalised, not raw — and why

**Normalised to sum to 1.0.** The name says shares; they are shares.

- The question the column exists to answer is *"is per-head influence balanced inside this user's
  collection?"* — inherently a ratio. The existing G6 gate already expresses the same idea as a
  max/min ratio of shares (`mood_distance_spec.rb:80-89`).
- Raw weighted squared deltas scale with how far the query sits from the collection, so they are not
  comparable across queries or users. Any analysis would normalise them anyway; doing it at write
  time means every row is directly comparable and no consumer can forget.

**What normalising loses, and how it is preserved:** magnitude and sample size. Both are kept as
separate scalars — `max_term` and `scored_count` — rather than smuggled into the shares. That is the
whole reason those two keys exist, and it should be said in the migration comment.

**A caution for whoever analyses this later, which belongs in the doc:** these shares are *not* the
same quantity as G6's imbalance. G6 uses per-head **variance across albums**; these use per-head
**squared distance from the query**. Since `E[Δ²] = Var(album_h) + (mean_h − q_h)²`, they coincide
only when the query sits at the collection's per-head mean and diverge otherwise. **G18 pins exactly
that relationship** so the difference is documented by a passing test rather than by folklore.

---

## 6. Gates

Standing bar for this ticket: a gate's **name is a claim and the code must make that claim**; every
gate asserts a **non-vacuity floor** before asserting its finding; **a test that recomputes its own
expected value instead of reading the published constant is the tell for a vacuous gate**. Existing
numbering runs to G15 (`mood_distance_spec.rb`), so these start at **G16**. Every mutation must be
**executed and its failure pasted into the PR**; a gate whose mutation was not run does not count.

| id | asserts | non-vacuity floor | mutation that must make it FAIL |
|---|---|---|---|
| **G16** | **one computation, two consumers.** Over the 321×12 fixture, `breakdown.per_head.values.sum` equals `(term * HeadWeights.max_distance)**2` within 1e-12 | assert 321 album rows and 12 query rows first | give `term` its own independent sum (e.g. a different weight lookup) → the invariant breaks |
| **G17** | **shares are shares.** Over the fixture, the six normalised values sum to 1.0 within 1e-12; each is in `0.0..1.0`; the key set equals `MoodVector::MOOD_HEADS` **as a set** | assert `scored_count == 321` before asserting the sum | return raw totals instead of normalised → sum ≠ 1.0; transpose two head keys → key-set/value assertion fails |
| **G18** | **shares relate to G6 exactly as claimed.** For a query placed at the per-head **mean of the fixture's calibrated coordinates**, the recorded shares equal G6's variance-based shares within 1e-9 — and for an off-centre query they measurably do **not** | assert both share vectors have six entries and that the off-centre control actually differs | drop the `(mean − q)²` offset reasoning by computing shares from variance instead → the off-centre control stops differing |
| **G19** | **the scored set is the full scored set.** With a fixture where `candidate_ids.size > @limit`, `scored_count` equals `candidate_ids.size`, not `@limit` | assert `candidate_ids.size > @limit` before comparing — otherwise the gate is trivially satisfied | move accumulation after `.first(@limit)` (`:28`), or into the post-filter set → `scored_count` collapses to 40 |
| **G20** | **never-instrumented is distinguishable from instrumented.** A row written without a retrieval reads `{}`; an instrumented row carries all three keys with `scored_count >= 1`; `scored_count == 0` never occurs | assert both rows exist in the example | change the column default to a six-zero hash → the two states become indistinguishable |
| **G21** | **`max_term` is the maximum, and respects the published bound.** Equals the max of the individually computed terms across the scored set, and is `<= 1.1902380714` — **read from the published G15 constant, not recomputed** | assert the scored set has > 1 member, so "max" is not trivially "the only one" | record the last term, or the mean, instead of the max |
| **G22** | **`Pipeline` persists what `CandidateRetrieval` computed.** With a retrieval stubbed to known shares, the created `RecommendationEvent.mood_head_shares` equals those values exactly | assert the stub's value is non-empty and differs from the column default | have `Pipeline` recompute the shares itself → diverges from the stub |
| **G23** | **the zero-distance edge case is handled.** A single-candidate run whose calibrated coordinates equal the query yields six `0.0` shares with `scored_count == 1`, and does not raise | assert the total squared distance really is 0 in the example | remove the zero guard → `ZeroDivisionError`/`NaN` |

---

## 7. PII and data exposure

**Low sensitivity, non-zero, and it needs two explicit decisions rather than a shrug.**

The column holds six floats, one float and one integer. It contains **no** album identifiers, no
titles, no artists, no query text, and no user identifier beyond the `user_id` FK already on the
row. It is **derived aggregate data over the user's own collection**, so it inherits exactly the
access controls of the row it sits on.

It is not nothing, though: a very low `danceability` share is a coarse signal that a user's library
is stylistically homogeneous. That is inference about a person's taste, not an identifier, and it is
strictly less revealing than `query_text`, which is already stored in plaintext on the same row.

Two decisions, both defaulting to "do not expose":

1. **Do not add `attribute :mood_head_shares` to `RecommendationEventResource`.** I checked: madmin
   lists attributes **explicitly**, so a new column is **not** auto-exposed. Leaving it out is the
   default-safe choice. If the owner wants admin visibility, add it as `form: false` — read-only —
   because it is a measurement, never an input.
2. **No API exposure, and none is at risk today.** `recommendations_controller.rb:12,32` and
   `feedback_controller.rb` render only `recommendation_event_id`, never the record, so nothing
   leaks by default. That must stay true — no serializer, no `as_json` override.

No new index means no new statistics surface, and no retention change: the column lives and dies
with its event row.

---

## 8. What I want the parallel reviewers to focus on

**Spec** — §3 and §5. Is the three-key shape right, and does `scored_count` versus
`candidates_considered` (§3.3) read unambiguously to someone who was not in this conversation?
Specifically challenge the normalisation choice: it is the one decision here that destroys
information, and §5's claim that `max_term` + `scored_count` preserve what matters is exactly the
kind of claim that should be argued with rather than accepted.

**Test** — §6, and the mutations above all else. Three things to be hard about: that **G19's floor
is real** (if the fixture's `candidate_ids.size` is not actually greater than `@limit`, the gate
proves nothing and passes anyway); that **G18 genuinely has a failing control** and is not just
asserting two equal things by construction; and that G21 **reads** `1.1902380714` from the published
source rather than recomputing it — a recomputed expected value is this ticket's signature failure.
Also verify all three `pipeline_spec.rb` `instance_double` sites (§4.3) were updated, not just the
one that failed first.

**Security** — §7, plus one thing outside it: confirm the migration cannot lock the table on a
production-sized `recommendation_events`, and confirm nothing in the feedback or recommendations
controllers can be induced to render the new column. The interesting question is not the data, which
is bland; it is whether anything auto-serialises a model's full attribute set anywhere in this app.

**Everyone** — §3.5. I am deliberately *not* fixing the nil-`mood_vector` `NoMethodError`, because
it is pre-existing in Option E and widening that diff during final review is the wrong trade. If a
reviewer thinks that is the wrong call, say so now rather than after both PRs land.

---

## 9. Evidence

Read at `bc6bc5d`: `candidate_retrieval.rb` (all 50 lines), `pipeline.rb` (all 57),
`mood_distance.rb`, `head_calibration.rb`, `head_weights.rb`, `recommendation_event.rb`,
`album.rb`, `db/schema.rb` (`recommendation_events`), `mood_distance_spec.rb` (all 139 lines, for
gate house style and the published constants), `pipeline_spec.rb` (the three `instance_double`
sites), `spec/support/mood_scale_fixture.rb`, `recommendation_event_resource.rb`,
`recommendations_controller.rb`, `feedback_controller.rb`, and `principal-optionE.md` §6.
Grepped for every `CandidateRetrieval` reference across `app/`, `spec/` and `lib/`.
No code was written and nothing was committed.
