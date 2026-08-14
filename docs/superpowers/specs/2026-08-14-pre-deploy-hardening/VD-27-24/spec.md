# SPEC REVIEW — vibe-doctor issue #24 (Tier 2)

**VERDICT: APPROVE** — with one scope item escalated to the dispatcher (not an implementer defect)
and two LOW observations.

- REPO: `/Users/lukeolson/projects/vibe-doctor`
- BASE_SHA: `5c9dfccda17ccf26af5267d099a391e3b2e882a8` (origin/main)
- HEAD_SHA: `d3ff0b93bba1ce19b55de090b9efbd609bcd560b`
- BRANCH: `fix/pre-deploy-record-and-clamp-coverage`
- Diff range reviewed: `git diff 5c9dfcc...d3ff0b9`, **commit `d3ff0b9` only**
- Out of scope per dispatch: `9445dbd` (issue #27 docs) — independently confirmed docs-only
- Implementer report read in full before review: `/tmp/maestri-reviews/VD-27-24/implementer.md`

Scope of `d3ff0b9`: one file, `spec/models/mood_vectors/essentia_mapper_spec.rb`, +25/-13.
`app/models/mood_vectors/essentia_mapper.rb` is unchanged across the whole range — verified, not
taken from the report.

**Headline:** the required `[head, direction]` product is real. I re-derived all eight clamp
mutations myself rather than trusting the implementer's matrix: **8/8 caught, each by exactly the
example its name promises.** The same harness reproduces the issue's own diagnosis of BASE — the
identical four bounds the issue said were missing are the four BASE misses. Names match bodies. No
spec asserts something other than what it claims.

---

## ANSWERS TO THE SIX QUESTIONS

### Q1 — Do the assertions match the example names exactly? **YES**

| Example (`essentia_mapper_spec.rb`) | Input | Asserts | Name honest? |
|---|---|---|---|
| `clamps softmax heads below the MoodVector range` :64 | `softmax_value: -0.1` | all four heads `eq(0.0)` | **yes** — below → lower bound |
| `clamps softmax heads above the MoodVector range` :73 | `softmax_value: 1.1` | all four heads `eq(1.0)` | **yes** — above → upper bound |

Confirmed twice: by reading, and behaviourally by the mutation table in Q-extra — every *lower*-bound
deletion is caught by the `below` example and by nothing else; every *upper*-bound deletion by the
`above` example and by nothing else. The names describe precisely what the bodies detect.

The BASE example this replaced was the dishonest one: named `clamps softmax heads to the MoodVector
range`, it asserted `mood_acoustic` → `0.0` and `mood_happy` → `0.0` while asserting `danceability`
and `mood_relaxed` → `1.0`. That is now gone.

### Q2 — Merge order: does an explicit override still beat `softmax_value`? **YES, and it is dead flexibility**

`essentia_mapper_spec.rb:5-24`. `softmax_value` is applied with `merge!` inside the guard (`:14-21`),
then `descriptors.merge(overrides)` is the return value (`:23`). Overrides are applied **last**, so
they win. Verified by execution:

```
softmax_value: -0.1 + mood_happy_musicnn: 0.75
  {danceability_musicnn: -0.1, mood_acoustic_musicnn: -0.1, mood_relaxed_musicnn: -0.1, mood_happy_musicnn: 0.75}
override wins? true
```

**It is not exercised anywhere.** Enumerating every caller in the file — the helper is used nowhere
else in `spec/` — only `:64` and `:73` pass `softmax_value`, and neither passes a softmax head
override alongside it:

```
5:    def descriptors_with(softmax_value: nil, **overrides)
28:      descriptors = descriptors_with(arousal_emomusic: 3.0)
49:      ... descriptors_with(valence_emomusic: native_value)
56:      ... descriptors_with(arousal_emomusic: 9.4)
57:      ... descriptors_with(arousal_emomusic: 0.6)
64:      ... descriptors_with(softmax_value: -0.1)      <- softmax_value, no head override
73:      ... descriptors_with(softmax_value: 1.1)       <- softmax_value, no head override
82:      descriptors = descriptors_with.except(:mood_happy_musicnn)
89:      descriptors = descriptors_with(bpm_rhythm2013: 120.0)
```

Correct precedence, untested. See **O1**.

### Q3 — Ruby falsiness: does `softmax_value: 0.0` behave as intended? **YES**

`essentia_mapper_spec.rb:14` guards with `if softmax_value`. In Ruby only `nil` and `false` are
falsy — `0.0` is truthy — so the block **runs** and `0.0` propagates to all four heads. Verified:

```
softmax_value: 0.0  -> {danceability_musicnn: 0.0, mood_acoustic_musicnn: 0.0,
                        mood_relaxed_musicnn: 0.0, mood_happy_musicnn: 0.0}
branch taken? true (0.0 is truthy in Ruby, so the block RUNS)
softmax_value: nil  -> {danceability_musicnn: 0.2, mood_acoustic_musicnn: 0.3}  (defaults kept)
softmax_value: false-> {danceability_musicnn: 0.2, mood_acoustic_musicnn: 0.3}  (silently ignored)
```

**No caller depends on it** — no caller passes `0.0` (see the Q2 enumeration). So this is
correct-but-unexercised, not a latent bug. `0.0` is in fact the interesting in-range boundary case
(the exact lower bound), and it would work if someone added it. The only oddity is
`softmax_value: false` being silently ignored, which is nonsense input; I am not raising it as a
finding.

### Q4 — REGRESSION CHECK: does the valence/arousal transposition property still hold? **YES — it holds, and it is guarded three ways**

This is the question the dispatch cared most about, so I verified it behaviourally rather than by
reading the comment.

First, the comment and the override both **survive verbatim**. `git show d3ff0b9:…` lines 27-29:

```ruby
    it "maps native descriptor values to symbol-keyed mood heads" do
      # The arousal override keeps valence/arousal transposition detectable despite equal helper defaults.
      descriptors = descriptors_with(arousal_emomusic: 3.0)
```

The diff hunk headers confirm this example was never touched — the edits are at `-5,2/+5,2`,
`-13/+13,11` (the helper) and `-53,7/+63,2`, `-61/+66,8`, `-64/+76`, `-66/+78` (the softmax
examples). The `maps native descriptor values` example at old line 16 / new line 27 is untouched
context. The helper's emomusic defaults are still both `5.0`, and the override path
(`descriptors.merge(overrides)`) still reaches `arousal_emomusic`.

Behavioural proof — I mutated the mapper to swap the two sources and replayed the HEAD examples:

```
transposed mapper output for maps_native input:
  {valence: 0.25, arousal: 0.5, danceability: 0.2, mood_acoustic: 0.3, mood_relaxed: 0.4, mood_happy: 0.6}
maps_native (HEAD helper)          RED (caught)
emomusic_table                     RED (caught)
arousal_two_direction              RED (caught)
```

**Not weakened.** The property is caught by three independent examples at HEAD, not just the one the
comment names. Nothing about the `softmax_value` refactor touches the emomusic path.

### Q5 — Did the emomusic two-direction coverage survive unchanged? **YES, byte-identical**

`clamps arousal emomusic values outside the native range` (`:55-59`, asserting `9.4` → `1.0` and
`0.6` → `0.0`) and the six-entry parameterized table (`:42-52`, covering `9.4, 9.0, 5.0, 3.0, 1.0,
0.6`) are both untouched — they appear only as diff context, never as `+`/`-` lines. Both pass at
HEAD, and both independently detect the transposition mutation (Q4). Confirmed unchanged.

### Q6 — Anything asserted that is not required, or required but not asserted?

**Nothing asserted that is not required.** The two examples are exactly the `[head, direction]`
product the issue's `## Required work` demands — 4 heads × 2 directions = 8 assertions, no more. The
clamp was kept, as required. The mapper was not modified. No gold-plating.

**One thing required by the issue and not delivered — but explicitly scoped out.** The issue's second
comment does not stop at coverage:

> Fixing the directional coverage is necessary but **not sufficient**. Whoever picks this up must
> also decide and record: when a descriptor arrives out of its declared range, does the app **skip
> the track** … or **include it saturated** (accept clamping as the policy, and add an assertion on
> the contributing count so the drift is at least observable)?

No such decision is recorded in `d3ff0b9`, and no assertion on the `contributing=` count
(`mood_grounding_service.rb:173`) exists. The implementer disclosed this rather than hiding it:

> "The issue comments discuss a future out-of-range policy decision after the planned thin-binding
> gem change. This task intentionally makes no such runtime-policy change, per the dispatch's
> coverage-only constraint."

This is a **conflict between the issue as written and the implementer's dispatch**, not an
implementer failure. Per my role I do not adjudicate that — see **ESCALATION** below.

---

## FINDINGS

### ESCALATION (for the dispatcher, not a defect) — issue #24 is not fully closed by `d3ff0b9`

The issue as written requires a recorded range-handling decision (skip vs. include-saturated) in
addition to the coverage fix, and calls coverage alone "not sufficient". The implementer was
dispatched coverage-only and complied and disclosed. **Recommendation: do not close #24 on this
commit** — either split the policy decision into its own issue and close #24's coverage half, or
reopen scope with the implementer. The issue's own sequencing note makes this load-bearing: the
decision must exist before the app repins past `v0.3.0`, because that is when the hazard window
opens. Routing that is your call, not mine.

### O1 — LOW — `softmax_value` override precedence is dead flexibility

`spec/models/mood_vectors/essentia_mapper_spec.rb:14-23`. The override-beats-`softmax_value`
precedence is correct but unreachable from any current caller (Q2). Not harmful; it is a helper, not
an assertion, and it costs nothing. Worth knowing only so nobody assumes it is covered. No change
required.

### O2 — LOW — the two new examples lost the head-independence detection the old one had; `maps native descriptor values` is now the sole guard

`spec/models/mood_vectors/essentia_mapper_spec.rb:63-79`. Because both new examples set all four
heads to the **same** value and expect the **same** output, a mapper that reads the wrong descriptor
for a head is invisible to them. The BASE example, which used distinct per-head values, caught it
incidentally. Proven with a crosswiring mutation (`mood_happy` reads `danceability_musicnn`):

```
BASE single softmax example        RED (caught)
HEAD 'below' example               GREEN (missed)
HEAD 'above' example               GREEN (missed)
maps_native (distinct defaults)    RED (caught)
```

**This is not a suite-level regression** — `maps native descriptor values` (`:27-38`) still catches
it, because the helper defaults are distinct (`0.2 / 0.3 / 0.4 / 0.6`) and it asserts the whole hash
with `eq`. I am reporting it as an observation, not a finding, for two reasons: the new examples never
claim to test head independence, and total suite coverage is unchanged.

The reason it is worth writing down at all: **`maps native descriptor values` is now the only thing
standing between a crosswired softmax head and a green suite.** If someone later "tidies" that
example to use the shared `softmax_value` helper — an easy and superficially attractive edit now that
the keyword exists — crosswiring detection disappears from the whole suite with no test turning red.
A one-line comment on that example, in the style of the transposition comment already above it, would
pin the property. Optional; no change required for this issue.

---

## VERIFIED BY EXECUTION

- Diff range and scope: mapper unchanged, only one non-docs file, `9445dbd` docs-only.
- Worktree at `d3ff0b9` is clean and matches the reviewed SHA.
- Target spec: 12 examples, 0 failures; both new examples present under their exact names.
- Full app suite at HEAD: **299 examples, 0 failures** (matches the implementer's claim).
- **All eight clamp mutations independently re-derived — 8/8 caught**, each by exactly one example.
- BASE's four blind spots reproduced, matching the issue's diagnosis exactly.
- Transposition mutation caught by three examples at HEAD (Q4).
- Crosswiring mutation missed by both new examples, caught by `maps_native` (O2).
- `softmax_value: 0.0 / nil / false` behaviour (Q3).
- Override-beats-`softmax_value` precedence (Q2).
- Helper caller enumeration: `softmax_value` passed at `:64` and `:73` only, never with a head
  override; helper unused outside this file.

## BELIEVED BY READING (not executed)

- That `mood_grounding_service.rb:173`'s `contributing=` count has no assertion anywhere. I read the
  issue's claim and did not grep the suite for it, because it is required only under the
  include-saturated branch of a decision that has not been made. Flagging as unverified rather than
  asserting it.
- The implementer's eight mutation **log files** under `/tmp/vd-27-24-rebased-*.log`. I did not read
  them; I re-derived the matrix independently instead, which is stronger evidence than checking their
  logs would have been.
- RuboCop and Brakeman results quoted in the implementer report. Not re-run — outside a spec review's
  remit and not load-bearing for this verdict.

---

## EVIDENCE

Harness (read-only; loads the mapper source, mutates **in memory**, writes nothing to either repo):
`…/114a28aa-a39b-4f12-b984-096f60d7375d/scratchpad/vd24_harness.rb`

### Diff range and scope

```
$ git -C /Users/lukeolson/projects/vibe-doctor diff --stat 5c9dfcc d3ff0b9 -- app/models/mood_vectors/essentia_mapper.rb
                                        <- empty: mapper unchanged

$ git -C … diff --name-only 5c9dfcc d3ff0b9 | grep -v '^docs/'
spec/models/mood_vectors/essentia_mapper_spec.rb

$ git -C … show --stat --format='' 9445dbd | grep -E 'app/|spec/'
  none — 9445dbd is docs-only, correctly out of scope

$ git -C … show --format='' -U0 d3ff0b9 | grep '^@@'
@@ -5,2 +5,2 @@      <- helper signature
@@ -13 +13,11 @@     <- helper body
@@ -53,7 +63,2 @@    <- softmax example replaced
@@ -61 +66,8 @@
@@ -64 +76 @@
@@ -66 +78 @@
                     (the "maps native descriptor values" example is untouched context)
```

### The diff under review

```diff
-    def descriptors_with(**overrides)
-      {
+    def descriptors_with(softmax_value: nil, **overrides)
+      descriptors = {
         valence_emomusic: 5.0,
         arousal_emomusic: 5.0,
         danceability_musicnn: 0.2,
         mood_acoustic_musicnn: 0.3,
         mood_relaxed_musicnn: 0.4,
         mood_happy_musicnn: 0.6
-      }.merge(overrides)
+      }
+      if softmax_value
+        descriptors.merge!(
+          danceability_musicnn: softmax_value,
+          mood_acoustic_musicnn: softmax_value,
+          mood_relaxed_musicnn: softmax_value,
+          mood_happy_musicnn: softmax_value
+        )
+      end
+
+      descriptors.merge(overrides)
     end
...
-    it "clamps softmax heads to the MoodVector range", :aggregate_failures do
-      descriptors = descriptors_with(
-        danceability_musicnn: 1.1,
-        mood_acoustic_musicnn: -0.1,
-        mood_relaxed_musicnn: 1.1,
-        mood_happy_musicnn: -0.1
-      )
-      result = described_class.new.call(descriptors)
+    it "clamps softmax heads below the MoodVector range", :aggregate_failures do
+      result = described_class.new.call(descriptors_with(softmax_value: -0.1))
+
+      expect(result.fetch(:danceability)).to eq(0.0)
+      expect(result.fetch(:mood_acoustic)).to eq(0.0)
+      expect(result.fetch(:mood_relaxed)).to eq(0.0)
+      expect(result.fetch(:mood_happy)).to eq(0.0)
+    end
+
+    it "clamps softmax heads above the MoodVector range", :aggregate_failures do
+      result = described_class.new.call(descriptors_with(softmax_value: 1.1))
 
       expect(result.fetch(:danceability)).to eq(1.0)
-      expect(result.fetch(:mood_acoustic)).to eq(0.0)
+      expect(result.fetch(:mood_acoustic)).to eq(1.0)
       expect(result.fetch(:mood_relaxed)).to eq(1.0)
-      expect(result.fetch(:mood_happy)).to eq(0.0)
+      expect(result.fetch(:mood_happy)).to eq(1.0)
     end
```

### Target spec at HEAD, in the implementer's worktree

```
$ git rev-parse HEAD           # in .worktrees/pre-deploy-record-and-clamp-coverage
d3ff0b93bba1ce19b55de090b9efbd609bcd560b
$ git status --porcelain=v1     # clean

$ bundle exec rspec spec/models/mood_vectors/essentia_mapper_spec.rb --format documentation
MoodVectors::EssentiaMapper
  #call
    maps native descriptor values to symbol-keyed mood heads
    maps native emomusic value 9.4 to 1.0
    maps native emomusic value 9.0 to 1.0
    maps native emomusic value 5.0 to 0.5
    maps native emomusic value 3.0 to 0.25
    maps native emomusic value 1.0 to 0.0
    maps native emomusic value 0.6 to 0.0
    clamps arousal emomusic values outside the native range
    clamps softmax heads below the MoodVector range
    clamps softmax heads above the MoodVector range
    rejects a missing descriptor
    rejects an unexpected descriptor

12 examples, 0 failures
```

### Harness control — the non-vacuity floor

Before trusting any RED, the unmutated mapper must be GREEN on every replayed example:

```
CONTROL: unmutated mapper must be GREEN on every example
  maps_native        PASS
  base_softmax       PASS
  head_below         PASS
  head_above         PASS
  arousal_two_dir    PASS
  emomusic_table     PASS
```

### The eight clamp bounds, independently re-derived

`lower` = that head's `clamp(v)` replaced with `[v, 1.0].min`; `upper` = with `[v, 0.0].max`.
The `BASE softmax` column replays the example this commit deleted.

```
  head             bound    | HEAD below             | HEAD above             | BASE softmax
  danceability     lower    | RED (caught)           | GREEN (missed)         | GREEN (missed)
  danceability     upper    | GREEN (missed)         | RED (caught)           | RED (caught)
  mood_acoustic    lower    | RED (caught)           | GREEN (missed)         | RED (caught)
  mood_acoustic    upper    | GREEN (missed)         | RED (caught)           | GREEN (missed)
  mood_relaxed     lower    | RED (caught)           | GREEN (missed)         | GREEN (missed)
  mood_relaxed     upper    | GREEN (missed)         | RED (caught)           | RED (caught)
  mood_happy       lower    | RED (caught)           | GREEN (missed)         | RED (caught)
  mood_happy       upper    | GREEN (missed)         | RED (caught)           | GREEN (missed)
```

Two independent conclusions from one table:

1. **HEAD catches 8/8.** Every lower deletion → the `below` example; every upper deletion → the
   `above` example. Exactly what the names promise, and each caught by one example only, so neither
   example is carrying the other.
2. **BASE caught 4/8, and the four it missed are precisely the four the issue named.** The issue
   said "danceability + mood_relaxed lose their lower bound; mood_acoustic + mood_happy lose their
   upper bound." The BASE column misses exactly `danceability lower`, `mood_relaxed lower`,
   `mood_acoustic upper`, `mood_happy upper`. The issue's diagnosis is confirmed and the fix closes
   exactly those four gaps — no more, no less.

### Q4 transposition, Q3 falsiness, Q2 precedence

```
Q4 REGRESSION: valence/arousal TRANSPOSITION
  transposed mapper output for maps_native input:
    {valence: 0.25, arousal: 0.5, danceability: 0.2, mood_acoustic: 0.3, mood_relaxed: 0.4, mood_happy: 0.6}
  maps_native (HEAD helper)          RED (caught)
  emomusic_table                     RED (caught)
  arousal_two_direction              RED (caught)

HEAD-INDEPENDENCE: mood_happy silently reads danceability_musicnn
  BASE single softmax example        RED (caught)
  HEAD 'below' example               GREEN (missed)
  HEAD 'above' example               GREEN (missed)
  maps_native (distinct defaults)    RED (caught)

Q3 RUBY FALSINESS
  softmax_value: 0.0  -> all four heads 0.0 ; branch taken? true (0.0 is truthy in Ruby)
  softmax_value: nil  -> defaults kept
  softmax_value: false-> silently ignored

Q2 MERGE ORDER
  softmax_value: -0.1 + mood_happy_musicnn: 0.75
    {danceability_musicnn: -0.1, mood_acoustic_musicnn: -0.1, mood_relaxed_musicnn: -0.1, mood_happy_musicnn: 0.75}
  override wins? true
```

### Full suite at HEAD

```
$ bundle exec rspec        # in .worktrees/pre-deploy-record-and-clamp-coverage @ d3ff0b9
299 examples, 0 failures
```

### Final repo state

Read-only throughout. No edits, no commits, no staging. All mutations were applied in memory inside
the scratch harness; the implementer's worktree was only read and only had `rspec` run in it.
