# SONANCE-MAIN-AUDIT — Q1: Is Essentia properly ported to Ruby?

# VERDICT: PORTED WITH RESERVATIONS

**Reviewer:** Keystone (Principal Engineer)
**Repos:** gem `/Users/lukeolson/projects/gems/mood_probe` @ `d514137` (== origin/main); app `/Users/lukeolson/projects/vibe-doctor` @ `1f8ad78` (tree-identical to origin/main `b26cf31`)
**Date:** 2026-08-13

---

## Which question I answered

The user asked whether Essentia is "properly ported to Ruby." Taken literally that question is
ill-posed and I did not answer it. **This gem does not port Essentia to Ruby.** There is no Ruby
reimplementation of any Essentia DSP. The gem is a *planner and marshaller*: Ruby builds a declarative
JSON plan, a Python subprocess (`python/sonance_extract.py`) drives real Essentia, and results return
as NDJSON. Not one line of signal processing is Ruby.

So the question I answered is the one that has an answer:

> **Is the Ruby surface a faithful and safe binding to Essentia — or does it distort, hide, or
> silently reinterpret what Essentia actually computes?**

**Answer: it is faithful and it is safe. Values are bit-exact, the serialization seam is defended in
depth, and both defenses are load-bearing. The reservations are not about wrong numbers — I could not
produce a wrong number. They are about one compute-doubling planner defect, one hard-coded opinion on
a universal path, two descriptors that no gate has ever pointed at real Essentia, and three registry
rows whose prose omits a reduction their metadata does disclose.**

Nothing here blocks the app. Nothing here corrupts a value.

---

## VERIFIED BY EXECUTION vs BELIEVED BY READING

### Verified by execution (I ran real Essentia 2.1-beta6-dev natively on this arm64 Mac)

| # | Claim | How |
|---|---|---|
| V1 | All **nine** registry descriptors extract successfully through the full Ruby `Extractor` against real Essentia + real model files, in **2.25 s** | `all9.rb`, descriptor list *derived* from `Registry.default.ids` |
| V2 | Float fidelity is **bit-exact**: float32 `42dd359f` → float64 `405ba6b3e0000000` (zero-filled widening), JSON text round-trips identically in Python and Ruby | struct/JSON round-trip |
| V3 | Essentia's 324 lines of `[ WARNING ]` chatter go to **stderr**; stdout is clean NDJSON, one line per path, in request order | stream separation |
| V4 | A non-finite Essentia output **cannot** reach Ruby. Two independent guards, **both proven load-bearing** | NaN/±Inf fake essentia + negative controls |
| V5 | Removing **both** guards puts bare `NaN` on the wire and Ruby raises `JSON::ParserError` | mutated copies in scratchpad |
| V6 | The planner emits **two** `RhythmExtractor2013` instances for `bpm` + `beat_confidence`; a one-instance plan is **accepted by Python** and yields **identical values** at **1.67× less wall clock** | timed 3-min track |
| V7 | Every graph emit is **forced** to `reduce: "mean_over_frames"`; omitted / `max_over_frames` / `none` all rejected; positive control accepted | `validate_plan` mutation matrix |
| V8 | Registering a second standalone algorithm without also adding `_ALGORITHM_PARAM_DOMAINS` raises an **uncaught `KeyError`**, not a `PlanValidationError` | scratch copy with a `Danceability` row |
| V9 | Default `rspec` run: **194 examples, 0 failures**, `exclude {essentia: true}` — **no real Essentia at all** | gem suite |
| V10 | **24/24 golden cells reproduce on native arm64** inside the calibrated `max(1e-4·|exp|, 1e-10)` bound; worst rel. dev **1.510e-05** (6.6× inside) | all 4 fixtures × 6 descriptors |
| V11 | `v0.2.0` **and** `v0.3.0` are **not** ancestors of `origin/main`; only `v0.1.0` is | `merge-base --is-ancestor` |
| V12 | `git clone --branch main --single-branch` fetches **only `v0.1.0`**; `v0.3.0` is **absent** and `git checkout v0.3.0` **fails**. `--depth 1` fetches **no tags** | scratch clones |
| V13 | **Bundler resolves the pin correctly.** It fetches exactly one ref — `refs/tags/v0.3.0` — into a bare mirror. Installed `lib/` and `python/` are **byte-identical to main** | real `bundle install` from github.com/Lhosb/sonance |
| V14 | Audio shorter than one MusiCNN patch (<3 s) yields a clean per-track `Sonance::InferenceError`, **not** a NaN mean | 0.2/0.5/1.0/2.0/3.0 s clips |
| V15 | All 6 model files fetch and **SHA-256 verify** through the gem's own `exe/sonance models fetch` | gem CLI |

### Believed by reading (not executed)

- That `mean(axis=0)` in float32 is numerically the intended reduction rather than an
  accumulate-in-float64 variant. I verified the *result* matches the x86_64 goldens; I did not audit
  numpy's accumulator dtype.
- That the CI release workflow actually runs the x86_64 Docker gate on every tag. I read the spec
  header and README instructions; I did not inspect workflow run history.
- Severity of F1 for the app rests on `EssentiaMapper::DESCRIPTORS` staying model-only.

---

## What I could NOT break (this is the core of the verdict)

I attacked the seam deliberately and it held.

**Fidelity.** A value Essentia produces arrives in Ruby unchanged. `Scalar#initialize` does
`value.to_f` on a `Float` that `JSON.parse` already produced — a no-op. There is **no rescaling, no
rounding, no float-to-string narrowing** anywhere in the gem. The float32 → float64 widening is exact
(low mantissa bits zero-filled), and `json.dumps` emits Python's shortest round-trip repr, which Ruby
parses back to the identical double. Verified at the bit level.

**Normalization stays out of the gem.** The gem returns native Essentia values — `valence_emomusic`
came back as `2.808…` on a 1.0–9.0 native scale. The app alone applies `(v - 1.0) / 8.0`
(`essentia_mapper.rb:44`). I found **no second normalization** in the gem. The factor-of-eight
double-normalization hazard flagged in CONTEXT is **not present**.

**The serialization killer is genuinely handled — in depth.** Python `json.dumps` emitting bare `NaN`
that Ruby `JSON.parse` rejects is the classic way this seam dies. Sonance stops it twice:

```
NAN_MODE=nan  → {"error":{"type":"malformed_output","message":"non-finite descriptor value: bpm_rhythm2013 is NaN"}}
NAN_MODE=inf  → ... is Infinity
NAN_MODE=ninf → ... is -Infinity
```

Layer 1 (`find_non_finite`, py:480) names the offending descriptor. Layer 2 (`allow_nan=False`,
py:506) is a real backstop — with layer 1 disabled it still produced
`descriptor serialization failed: Out of range float values are not JSON compliant`. With **both**
removed the wire carried `"bpm_rhythm2013": NaN` and Ruby died with
`JSON::ParserError: unexpected token 'NaN,' at line 1 column 127`.

That last line is the whole point. Both guards are load-bearing, and the design choice is correct:
they convert what would be a **batch-fatal** `BackendError` (killing all N tracks in the batch, since
`parse_results` rescues `JSON::ParserError` into a `FatalError`) into a **per-track** `TrackError`.
One bad track does not poison a batch. This is the best-engineered part of the gem.

**Honesty about reduction — at the metadata layer.** `mean_over_frames` is an arithmetic mean over the
frame axis (`value.mean(axis=0)`, py:458), applied **before** class selection, so the scalar is the
mean of a class probability across frames. Every affected value carries
`provenance.reduction == :mean_over_frames`. The gem does **not** pretend a frame-wise algorithm is
natively scalar. The README is likewise accurate — it says the gate "compares all **six** descriptor
values," which is exactly true and does not overclaim to nine.

---

## FINDINGS

### F1 — IMPORTANT — Planner runs `RhythmExtractor2013` twice for two outputs of one invocation
**`lib/sonance/plan.rb:100-103`**

`FromAlgorithm` is `Data.define(:name, :output, :params, :sample_rate)` — the dedup key includes
`output`. So `.uniq` at plan.rb:100 sees `bpm` and `confidence` as distinct invocations:

```
algorithms=[{ref:"a0", name:"RhythmExtractor2013", params:{method:"multifeature"}, sample_rate:44100},
            {ref:"a1", name:"RhythmExtractor2013", params:{method:"multifeature"}, sample_rate:44100}]
```

Two identical extractors each run full multifeature beat tracking over the whole file. Python's
`execute_plan` (py:446-450) already builds **both** `bpm` and `confidence` from a single call, so `a1`
recomputes something `a0` already has.

*Failure scenario:* a caller requesting `bpm_rhythm2013` + `beat_confidence_rhythm2013` pays **1.67×
wall clock**. Measured on a 3-minute track, 3 runs each: two-instance **2.89 / 2.87 / 2.92 s**,
one-instance **1.72 / 1.74 / 1.74 s** — ~1.15 s wasted per track. Over a 10k-track library that is
~3.2 CPU-hours of pure waste.

*Why it is a design defect, not a tuning nit:* the model path gets this layering **right** —
`graph_models_for` dedupes by model id and pushes class selection onto the emit as
`take:{index:}`. The algorithm path conflates *invocation identity* (`name`+`params`+`sample_rate`)
with *output selection* (`output`), which belongs on the emit. The wire protocol already supports the
correct form — I ran a hand-written one-instance plan and Python accepted it, returning
**identical values** (`bpm 123.3450927734375`, `confidence 1.5975282192230225`). Only the Ruby planner
fails to emit it.

*Blast radius today:* **none for vibe-doctor.** `EssentiaMapper::DESCRIPTORS`
(`app/models/mood_vectors/essentia_mapper.rb:5-13`) is the six model descriptors only — no algorithm
rows. The defect is latent, and it fires the moment anyone adds BPM to the app.

### F2 — IMPORTANT — `mean_over_frames` is mandated on every graph emit: the next instance of the precedent shape
**`python/sonance_extract.py:258-262`**

The dispatch asked me to look for the successor to the `validate_params`/RhythmExtractor2013 leak.
**I found it, and it is on the graph side, not the algorithm side.**

Credit first: the old leak is genuinely fixed. `_ALGORITHM_MINIMUM_SPANS.get(algorithm_name)`
(py:360) returns `None` and early-returns for any algorithm without a span rule, so RhythmExtractor's
20-BPM tempo rule no longer touches other algorithms. That was the right fix.

But the same shape now sits one layer over:

```python
if source_ref in graph_refs:
    if emit_spec.get("reduce") != "mean_over_frames":
        raise PlanValidationError(f"{location}.reduce must be mean_over_frames for graph output")
```

Every graph output — for **all time, for every graph algorithm** — must be mean-reduced. Verified:

```
reduce omitted on a graph emit    -> REJECTED
reduce='max_over_frames'          -> REJECTED
reduce='none'                     -> REJECTED
reduce='mean_over_frames' (ctl)   -> ACCEPTED
```

This is MusiCNN's frame-wise-patch assumption hard-coded on the path every graph descriptor must
traverse — structurally identical to the RhythmExtractor precedent, just relocated. The Ruby side
mirrors it: `Planner#emit_from_model` unconditionally writes `reduce: model.reduction.to_s`
(plan.rb:145), and `Registry.model` hard-codes `reduction: :mean_over_frames` for **every** model
(registry.rb:196). The `reduction` field is presented as per-model configuration but has exactly one
legal value; a model that is not frame-wise, or that wants max/median/last-frame, **cannot be
expressed at all**.

*Failure scenario:* the first non-MusiCNN graph model — a whole-song classifier emitting a single
frame, or a head where max-pooling is upstream's documented recipe — cannot be added without editing
the universal validator. The registry row that looks like it configures reduction does not.

*Note:* this is a **lock-in** finding, not a correctness one. `mean_over_frames` is right for all six
shipped MusiCNN heads.

### F3 — IMPORTANT — Two of nine descriptors have never met real Essentia in any gate
**derived from the specs, not transcribed**

Real-Essentia coverage, derived by reading every spec's descriptor list and its Essentia source:

| Spec | Essentia | Descriptors touched |
|---|---|---|
| `integration/essentia_golden_spec.rb` | **real**, x86_64-Docker-locked | valence, arousal, danceability, mood_acoustic, mood_relaxed, mood_happy |
| `integration/essentia_offline_spec.rb` | **real**, runs on any host | bpm_rhythm2013, mood_happy_musicnn |
| `integration/python_plan_executor_spec.rb` | **fake** (`spec/support/fake_essentia`) | valence, mood_happy, mood_relaxed, embedding, beat_confidence |
| `integration/python_seam_spec.rb` | **fake** | valence, arousal, mood_happy |
| `integration/signal_death_spec.rb` | **fake** | mood_happy |

Union of real-Essentia coverage = **7 of 9**. Never asserted against real Essentia by any spec:

- **`embedding_musicnn`** — the 200-element vector
- **`beat_confidence_rhythm2013`**

*Failure scenario:* `embedding_musicnn` declares `shape: 200` (registry.rb:233) and `Vector#initialize`
raises `MalformedOutputError` on any length mismatch (value.rb:120-123). Nothing in the suite has ever
confirmed the real `model/dense/BiasAdd` layer is 200-wide after `mean(axis=0)`. An Essentia or model
revision changing that width ships green and fails in production on the first track. **I confirmed by
execution that it is 200 and all-finite today** — so the assertion is correct; it is simply
*ungated*.

Compounding it: **the default `rspec` run exercises no real Essentia whatsoever** — `194 examples, 0
failures, exclude {essentia: true}`. The only unconditional real-Essentia gate is
`essentia_offline_spec.rb`, which does **not** call `CanonicalEssentiaEnvironment.verify!` and
therefore passes on this arm64 Mac. That asymmetry is undocumented.

*And the x86_64 lock is stricter than the evidence requires.* I measured all four golden fixtures ×
six descriptors on **native arm64**:

```
cells=24  failures=0
worst relative deviation 1.510e-05 on white_noise.mood_acoustic_musicnn (bound 1.0e-04 => 6.6x inside)
host_cpu=arm64  arch=arm64
```

Every cell passes the calibrated bound. Note the honest nuance: arm64's worst deviation (1.51e-05) is
~3.5× larger than the recorded x86_64-to-x86_64 worst (4.369e-06 on EPYC 9V74), so arm64 **is**
measurably further from the goldens — which actually **validates** 1e-4 as well-calibrated. The
canonical-environment gate is defensible as a *golden-regeneration provenance* policy. It is
**over-applied as a functional-coverage gate**: full nine-descriptor functional verification is
available on this laptop in **2.25 seconds** and nobody runs it.

### F4 — MINOR — Three registry rows omit the reduction from their prose
**`lib/sonance/registry.rb:254, 234`**

Machine metadata is correct everywhere — I confirmed `provenance.reduction == :mean_over_frames` on
all seven model-backed values including the embedding. The prose `notes` are incomplete:

| descriptor | reduction | notes disclose it? | notes text |
|---|---|---|---|
| valence_emomusic | mean_over_frames | **no** | "Native emoMusic arousal-valence output." |
| arousal_emomusic | mean_over_frames | **no** | "Native emoMusic arousal-valence output." |
| danceability / mood_* (4) | mean_over_frames | yes | "Mean-reduced frame-wise softmax probability." |
| **embedding_musicnn** | mean_over_frames | **no** | "Penultimate-layer MSD MusiCNN embedding." |

`embedding_musicnn` is the one that matters. A "penultimate-layer embedding" that is silently
**time-averaged** is a materially different object from a frame-wise embedding — anyone using it for
similarity search or as a downstream feature would reasonably assume per-frame. The word "Native" on
valence/arousal is also load-bearing in the wrong direction: it means *native range*, but reads as
*unmodified Essentia output*.

### F5 — MINOR — The "Adding an algorithm" checklist omits a required fourth site
**`README.md:56-61`, `python/sonance_extract.py:446`**

README lists three sites: `_ALGORITHM_PARAMS`, `_ALGORITHM_PARAM_DOMAINS`, `build_pipeline`. There is
a **fourth**: the output-mapping branch in `execute_plan` (py:446), which converts
RhythmExtractor2013's 5-tuple into `{"bpm": output[0], "confidence": output[2]}`. `execute_plan`
appears **nowhere** in the README. Omitting that branch leaves `algorithm_outputs[ref]` unset and
produces a bare `KeyError` at emit time.

Relatedly, `validate_params` indexes `_ALGORITHM_PARAM_DOMAINS[algorithm_name]` (py:340) and
`_ALGORITHM_PARAM_DEFAULTS[algorithm_name]` (py:364) directly. Registering an algorithm in
`_ALGORITHM_PARAMS` alone gives:

```
validate_plan -> UNCAUGHT KeyError: 'Danceability'
```

`main()` catches only `OSError` / `JSONDecodeError` / `PlanValidationError`, so this surfaces as a
Python traceback and exit 1 rather than the clean `sonance plan invalid: …` / exit 2 contract. **In
fairness the README does document adding `_ALGORITHM_PARAM_DOMAINS`**, so this is a documented
coupling with an unfriendly failure mode, not a hidden trap. Severity minor on that basis.

### F6 — MINOR — Essentia's stderr chatter becomes the exception message
**`lib/sonance/backends/essentia_python.rb:185-192`**

`raise_for_fatal_exit!` uses `result.stderr.to_s.strip` as the raised message. A normal run emits
**324 lines / 24,948 bytes** of `[ WARNING ] No network created…`. Any nonzero exit therefore raises a
`ConfigurationError` or `BackendError` whose message is ~25 KB of noise with the real cause buried in
it — into Solid Queue job logs and error tracking.

### F7 — MINOR — No fixture is shorter than one MusiCNN patch
**`spec/fixtures/sonance/audio/*.wav`**

All five committed fixtures are **exactly 10.000000 s**. The sub-patch path is untested. I exercised
it: 0.2 / 0.5 / 1.0 / 2.0 s all return a clean per-track
`Sonance::InferenceError: Error cannot convert argument LIST_EMPTY to MATRIX_REAL`; 3.0 s succeeds.
**The behaviour is correct** — but it is correct because Essentia raises before `mean(axis=0)` can
average an empty axis into NaN, not because the gem designed for it. Short intros, interludes, and
silence-trimmed clips are realistic production inputs sitting on an ungated boundary.

---

## ARCHITECTURAL RULING — the broken tag ancestry (CONTEXT fact 3)

**This is mine to call, so I will call it plainly: do not re-tag, do not rewrite history, and do not
treat this as a deployability defect. Fix the release procedure going forward and record what
shipped.**

### What is actually true

Confirmed independently:

```
v0.1.0   ancestor_of_main=YES
v0.2.0   ancestor_of_main=NO
v0.3.0   ancestor_of_main=NO
```

It is **not** a one-off. Every release since v0.1.0 sits on pre-squash branch history. The tagged
commit `6639397` is reachable only from `feat/essentia-gem-v2-phase-a` (local **and** on origin) and
from the tag ref itself. Runtime code at tag and main is identical — only two spec files differ.

### What it does NOT cost

**It does not break deployment, and I proved that rather than assuming it.** A real `bundle install`
against github.com/Lhosb/sonance succeeded. Bundler fetches into a bare mirror and the cache contains
exactly one ref:

```
refs/tags/v0.3.0    →  66393972a8b57ee116afec0fbeb879a0c410dbca
```

Bundler resolves the tag **by name**; main's history is irrelevant to it. The installed `lib/` and
`python/` are byte-identical to main. Anyone reporting this as "the app cannot install its gem" is
wrong.

### What it does cost

1. **Provenance is unanswerable from main.** The app runs a tree not reachable from the default
   branch. `git log`, `git describe`, `git blame`, and changelog tooling walking main will never see
   what shipped. "What is in production?" cannot be answered from `main`. That is the real cost and
   it is not cosmetic — it is exactly the auditability this gem otherwise invests heavily in
   (PROVENANCE.md files, model SHA-256 pinning, a `Provenance` value object).

2. **One concrete propagation hazard, verified.** Git fetches tags *reachable from the fetched refs*.
   Therefore:

   ```
   git clone --branch main --single-branch  →  tags: [v0.1.0]        v0.3.0 ABSENT, checkout FAILS
   git clone --depth 1 --branch main         →  tags: []              v0.3.0 ABSENT
   ```

   Any mirror, migration, vendoring step, or Docker build cache that clones main narrowly **drops
   v0.3.0 silently**. Bundler does not do this today; a future mirror or a repo migration plausibly
   would, and the failure would appear as an unresolvable pin far from its cause.

3. **The tag is the single point of failure.** Nothing on main pins `6639397`. If the tag is ever
   moved or deleted — re-tagging a release is a routine mistake — the pin silently changes meaning or
   breaks, and **no main-side review would reveal it**, because the tagged tree is not on main.

### Ruling

- **Do not re-tag `v0.3.0` or rewrite gem history.** `Gemfile.lock` records `cf8e613…` (the annotated
  tag object). Moving or recreating the tag would invalidate a resolved, working, reviewed pin to buy
  tidiness. That trade is wrong.
- **Do not delete `origin/feat/essentia-gem-v2-phase-a`** until the app is repinned. It is currently
  the only branch reachability the tagged commit has. (The tag ref alone protects the object from GC,
  but the branch is what protects it from narrow-clone loss.)
- **Change the release procedure:** tag **after** the squash-merge, on the main-side commit. This is a
  one-line process fix and it prevents recurrence. It is the whole remedy.
- **For the next release,** cut the tag on a main commit. Because tag and main runtime code are
  already identical, repinning the app to a main-reachable tag is a **behavioural no-op** — it costs
  nothing and restores provenance. Do it at the next routine bump, not as an emergency.
- **Record the mapping now,** in the gem's `CHANGELOG.md`: `v0.3.0 → 6639397 (pre-squash); merged to
  main as 7aabc96`. That one line makes the history answerable from main without touching a single
  ref, and it is the highest value-per-risk action available.

I am explicitly **not** escalating this to blocking. It is a process defect with a real auditability
cost and a bounded, non-imminent failure mode.

---

## What I looked for and did NOT find

Absence stated deliberately, because in this audit it is meaningful:

- **No double-normalization.** I searched the gem for any `/8.0`, `- 1.0`, or range mapping. The gem
  returns native values; only `EssentiaMapper` rescales. The factor-of-eight hazard is not present.
- **No lossy transform anywhere.** No rounding, no `to_s`/`to_f` narrowing, no precision reduction, no
  unit conversion. I looked at every assignment on the value path.
- **No stale descriptor ids.** All nine ids derived from `Registry.default.ids` at runtime match the
  ids in every plan fixture, golden file, and the app's `DESCRIPTORS`. I derived rather than
  transcribed. The prefix-heuristic weakness in `descriptor_id_integrity_spec.rb:23-31` is real (the
  `%i[]` scan only fires when a *known* id is already present or an 80-char `descriptor` context
  matches, so a wholly-renamed list can slip), but I found **no actual stale id** on main.
- **No stdout contamination.** Essentia's 324 warning lines all go to stderr; NDJSON framing is
  intact. This was my strongest hypothesis for a hidden corruption path and it is clean.
- **No path/ordering confusion in batch mode.** `parse_line` asserts `payload["path"] == requested_path`
  and `validate_result_count!` asserts line count; verified with a 3-path batch returning in order.

---

## EVIDENCE

Scratchpad (all mutations outside both repos):
`/private/tmp/claude-502/-Users-lukeolson-projects-vibe-doctor--maestri-roles-10b2447a-4f51-47b3-ae81-0c4d6b15261a/1eb6cc9f-48fd-43fc-9e0f-74d503624c80/scratchpad`

**Environment**
```
$ python3 -c "import essentia, essentia.standard; print('essentia', essentia.__version__)"
essentia 2.1-beta6-dev
$ python3 -V   → Python 3.11.6      host_cpu=arm64  arch=arm64
```

**V1 — all nine descriptors, real Essentia, full Ruby Extractor** (descriptors derived from `Registry.default.ids`)
```
requesting 9 descriptors: valence_emomusic, arousal_emomusic, danceability_musicnn, mood_acoustic_musicnn,
  mood_relaxed_musicnn, mood_happy_musicnn, embedding_musicnn, bpm_rhythm2013, beat_confidence_rhythm2013
elapsed 2.25s
valence_emomusic             2.808534622192383      native_range=1.0..9.0     units=:unitless    reduction=:mean_over_frames
arousal_emomusic             6.805241584777832      native_range=1.0..9.0     units=:unitless    reduction=:mean_over_frames
danceability_musicnn         0.9995235204696655     native_range=0.0..1.0     units=:probability reduction=:mean_over_frames
mood_acoustic_musicnn        1.4961327110540878e-07 native_range=0.0..1.0     units=:probability reduction=:mean_over_frames
mood_relaxed_musicnn         0.0011443665716797113  native_range=0.0..1.0     units=:probability reduction=:mean_over_frames
mood_happy_musicnn           0.018734250217676163   native_range=0.0..1.0     units=:probability reduction=:mean_over_frames
embedding_musicnn            VECTOR len=200  head=[-1.00958, 1.7715, -2.14959]  all_finite=true
bpm_rhythm2013               123.3450927734375      native_range=nil          units=:bpm         reduction=nil
beat_confidence_rhythm2013   1.5975282192230225     native_range=nil          units=:unitless    reduction=nil
```

**V2 — bit-exact float round trip**
```
float32 bits : 42dd359f
as float64   : 110.60472869873047
json text    : 110.60472869873047
reparsed==   : True
ruby Float   : 110.60472869873047
ruby bits    : 405ba6b3e0000000
to_f identity: true
```

**V3 — stdout is clean NDJSON, stderr carries the chatter**
```
$ python3 python/sonance_extract.py sine_440.wav clicks_44100.wav white_noise.wav \
    --models-dir $SC/models --plan-file spec/fixtures/sonance/plans/algorithm_only.json 2>$SC/stderr.txt
{"path": ".../sine_440.wav", "features": {"bpm_rhythm2013": 110.60472869873047}}
{"path": ".../clicks_44100.wav", "features": {"bpm_rhythm2013": 120.0335693359375}}
{"path": ".../white_noise.wav", "features": {"bpm_rhythm2013": 123.3450927734375}}
EXIT=0
$ wc -l < stderr.txt → 324        $ wc -c < stderr.txt → 24948
```

**V4/V5 — the serialization seam, guards intact then broken (negative controls)**
```
=== guards INTACT, fake essentia returning non-finite bpm ===
NAN_MODE=nan  → {"path":"...","error":{"type":"malformed_output","message":"non-finite descriptor value: bpm_rhythm2013 is NaN"}}       exit=0
NAN_MODE=inf  → ... "bpm_rhythm2013 is Infinity"                                                                                        exit=0
NAN_MODE=ninf → ... "bpm_rhythm2013 is -Infinity"                                                                                       exit=0

=== A) layer 1 (find_non_finite) REMOVED, allow_nan=False intact ===
{"path":"...","error":{"type":"malformed_output","message":"descriptor serialization failed: Out of range float values are not JSON compliant"}}

=== B) BOTH guards removed — what reaches the wire ===
{"path": ".../sine_440.wav", "features": {"bpm_rhythm2013": NaN, "beat_confidence_rhythm2013": 3.0}}

=== C) Ruby parsing that exact line ===
JSON::ParserError: unexpected token 'NaN,' at line 1 column 127
```

**V6 — duplicate RhythmExtractor2013 (F1)**
```
PLAN (from Extractor#plan_for for [bpm_rhythm2013, beat_confidence_rhythm2013]):
  algorithms=[{ref:"a0", name:"RhythmExtractor2013", params:{method:"multifeature"}, sample_rate:44100},
              {ref:"a1", name:"RhythmExtractor2013", params:{method:"multifeature"}, sample_rate:44100}]

3-minute track, 3 runs each:
  TWO-INSTANCE (what the gem emits):  real 2.89 / 2.87 / 2.92
  ONE-INSTANCE (hand-written plan):   real 1.72 / 1.74 / 1.74
Both produce identical values:
  {"bpm_rhythm2013": 123.3450927734375, "beat_confidence_rhythm2013": 1.5975282192230225}
```

**V7 — reduce mandate (F2), with positive control**
```
reduce omitted on a graph emit       -> REJECTED: emit[1].reduce must be mean_over_frames for graph output
reduce='max_over_frames'             -> REJECTED: emit[1].reduce must be mean_over_frames for graph output
reduce='none'                        -> REJECTED: emit[1].reduce must be mean_over_frames for graph output
reduce='mean_over_frames' (ctl)      -> ACCEPTED
```

**V8 — second-algorithm generalization trap (F5)**
```
_ALGORITHM_PARAMS = { "Danceability": {"maxTau": int}, "RhythmExtractor2013": {...} }
validate_plan -> UNCAUGHT KeyError: 'Danceability'
(main() catches only OSError/JSONDecodeError/PlanValidationError -> traceback + exit 1)
```

**V9 — default suite runs no real Essentia**
```
$ bundle exec rspec
Run options: exclude {essentia: true}
194 examples, 0 failures

$ ESSENTIA_SPECS=1 bundle exec rspec spec/integration/essentia_golden_spec.rb spec/integration/essentia_offline_spec.rb
14 examples, 6 failures    # all 6 from essentia_golden_spec via CanonicalEssentiaEnvironment.verify! rejecting arm64;
                           # all of essentia_offline_spec (real Essentia bpm) PASSED on arm64
```

**V10 — arm64 reproduces the x86_64 goldens inside the calibrated bound**
```
cells=24  failures=0
worst relative deviation 1.510e-05 on white_noise.mood_acoustic_musicnn (bound 1.0e-04 => 6.6x inside)
host_cpu=arm64  arch=arm64
(sample rows)
chirp       mood_relaxed_musicnn  exp=0.9997396469116211      arm64=0.9997396469116211      absdelta=0.000e+00  tol=9.997e-05  PASS
clicks      mood_acoustic_musicnn exp=9.578188837622292e-06   arm64=9.578201570548117e-06   absdelta=1.273e-11  tol=9.578e-10  PASS
white_noise mood_acoustic_musicnn exp=1.4961101157950907e-07  arm64=1.4961327110540878e-07  absdelta=2.260e-12  tol=1.000e-10  PASS
```

**V11/V12/V13 — tag ancestry, clone behaviour, Bundler resolution**
```
$ git merge-base --is-ancestor v0.3.0^{commit} origin/main   → NO
v0.1.0 ancestor_of_main=YES   v0.2.0 ancestor_of_main=NO   v0.3.0 ancestor_of_main=NO
tag object cf8e613e9a9b3b3b576df4e20e61e63ec25dffe6  peels to  66393972a8b57ee116afec0fbeb879a0c410dbca
$ git branch -a --contains v0.3.0^{commit}
  feat/essentia-gem-v2-phase-a
  remotes/origin/feat/essentia-gem-v2-phase-a
$ git diff --stat v0.3.0^{commit}..origin/main -- lib python exe sonance.gemspec   → (empty)
$ git diff --stat v0.3.0^{commit}..origin/main
 spec/canonical_essentia_environment_spec.rb    | 130 ++++++++++++++++++-----
 spec/support/canonical_essentia_environment.rb |  27 ++++-

$ git clone --branch main --single-branch file://.../mood_probe
  tags: v0.1.0          v0.3.0 resolves: ABSENT
  git checkout v0.3.0 → error: pathspec 'v0.3.0' did not match any file(s) known to git
$ git clone --depth 1 --branch main --single-branch ...
  tags: []              v0.3.0 resolves: ABSENT -- pin would fail

$ bundle install   # Gemfile: gem "sonance", git: "https://github.com/Lhosb/sonance.git", tag: "v0.3.0"
Fetching https://github.com/Lhosb/sonance.git
Bundle complete! 1 Gemfile dependency, 1 gem now installed.
Gemfile.lock: revision: cf8e613e9a9b3b3b576df4e20e61e63ec25dffe6 / tag: v0.3.0 / sonance (0.3.0)
refs in bundler's bare cache: refs/tags/v0.3.0    (that ref only)
lib IDENTICAL to main ; python IDENTICAL to main
```

**V14 — sub-patch-length audio (F7)**
```
fixture durations: chirp 10.0s  clicks_44100 10.0s  clicks 10.0s  sine_440 10.0s  white_noise 10.0s
0.2  s InferenceError  Error cannot convert argument LIST_EMPTY to MATRIX_REAL
0.5  s InferenceError  ...
1.0  s InferenceError  ...
2.0  s InferenceError  ...
3.0  s OK    mood_happy=0.00039893158827908337 embedding_len=200
```

**V15 — model fetch + SHA-256 verification via the gem's own CLI**
```
$ ruby -Ilib exe/sonance --models-dir $SC/realmodels models fetch
[6 CC-BY-NC-ND-4.0 license notices printed]
Models fetched and verified
  msd-musicnn-1.pb 3197999 | danceability/mood_acoustic/mood_happy/mood_relaxed 82458 each | emomusic 82460
```

**Repo cleanliness — verified at finish, both read-only throughout**
```
/Users/lukeolson/projects/gems/mood_probe   ## main...origin/main                     d514137  (clean)
/Users/lukeolson/projects/vibe-doctor       ## docs/essentia-gem-v2-design...origin/…  1f8ad78
   ?? docs/superpowers/specs/2026-08-10-.../phase-a/whole-branch/   ← pre-existing at session start, not mine
```
I did not modify, stage, commit, push, or repin anything in either repo. All mutated copies
(`broken_layer1.py`, `broken_both.py`, `two_algos.py`, fake essentia, plans, clones, bundle test) live
in the scratchpad.

---

## Summary of the verdict

**PORTED WITH RESERVATIONS** — and the reservations are deliberately not "approve."

The binding is faithful. I tried hard to make it produce a wrong number and could not. Fidelity is
bit-exact, normalization is correctly located in the app rather than the gem, the NaN/Infinity
serialization trap is defended twice over with both layers proven load-bearing, batch framing is
verified, and per-track errors are correctly isolated from batch-fatal ones. That is better than most
subprocess bindings I review.

It falls short of clean approval on four counts. One planner defect doubles the cost of the rhythm
path (F1) — latent for the app today, real the moment BPM is added. One algorithm family's assumption
is hard-mandated on the path every graph descriptor must traverse (F2) — the precedent shape has
moved, not died. Two of nine descriptors have never been pointed at real Essentia by any gate (F3),
while full nine-descriptor verification turns out to take 2.25 seconds on this laptop. And the
gem's prose under-discloses a reduction its metadata discloses correctly (F4) — most consequentially
on an "embedding" that is silently time-averaged.

None of these are merge-blocking, and none of them justify changing anything about how the app is
pinned today.

**Recommended order:** F3 (cheapest, highest confidence gain — an unconditional real-Essentia smoke
gate covering all nine, no Docker required), then F1 (contained, ~1.15 s/track), then F4 (one-line
honesty fix), then F2 as a design decision to take deliberately rather than by default. F5–F7 are
housekeeping.
