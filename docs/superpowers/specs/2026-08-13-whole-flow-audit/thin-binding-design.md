# Sonance thin-binding design — issues #9, #14, #15

**Author:** Keystone (Principal Engineer) · **Date:** 2026-08-14 · **Tier 1, design only**
**Repos (read-only):** gem `Lhosb/sonance` @ `d514137` · app `Lhosb/vibe-doctor` @ `1f8ad78`
**Status:** written incrementally; each section lands as it is finished.

---

## Headline rulings

| Item | Issue | Ruling |
|---|---|---|
| 1 — reduction | #9 | `reduce` moves onto `FromModel`. `:none` returns a `Series`. Time axis comes from **registry model rows**, never from Python and never hardcoded in the executor. **No other reduction earns a place now.** |
| 2 — registry | #14 | The mechanism **already exists and works at v0.3.0**. Deliver ergonomics, docs, a sync gate, and one **new Ruby-side enum gate** that is currently missing. |
| 3 — range | #15 | **Option 2 — report, don't veto.** Split `MalformedOutputError`'s two meanings; out-of-range becomes state on `Value`, malformed output stays a fatal `TrackError`. |
| Version | — | **0.4.0** = items 1+2. **0.5.0** = item 3 (the breaking one). |
| Order | — | vibe-doctor#24 → gem 0.4.0 → gem 0.5.0 → app range handling → **repin**. The hazard window opens at the **repin**, not at the gem release. |

---

## 0. THE LOAD-BEARING FINDING — recovered and stated first

**Reordering `reduce` and `take` changes production values in the last ULP, and every committed
fixture is too short to detect it.**

I had assumed that "mean over the frame axis, then select the class column" and "select the class
column, then mean" are interchangeable, and that item 1 could therefore restructure the executor
freely. **That assumption is false.** Measured against real Essentia:

```
file          frames         mean_then_index        index_then_mean  bit-identical    rel diff
white_noise        5    0.018734250217676163   0.018734250217676163           True   0.000e+00
chirp              5    0.001669647404924035   0.001669647404924035           True   0.000e+00
sine_440           5   0.0008378202328458428  0.0008378202328458428           True   0.000e+00
clicks             5     0.06125427410006523    0.06125427410006523           True   0.000e+00
t30               19   0.0009184085647575557  0.0009184085647575557           True   0.000e+00
t60               39   0.0009330970351584256  0.0009330969769507647          False   6.238e-08
t90               59   0.0009378259419463575  0.0009378259419463575           True   0.000e+00
track180         119    0.024122385308146477   0.024122387170791626          False   7.722e-08
```

`h.mean(axis=0)[0]` walks a strided column of a `(n, 2)` float32 matrix; `h[:, 0].mean()` walks a
contiguous `(n,)` view. NumPy's pairwise summation blocks the two differently, so the float32
rounding differs. The divergence is **frame-count dependent and non-monotonic** — 39 and 119 frames
diverge, 19 and 59 do not.

### Why this is the most important thing in this document

1. **All four committed golden fixtures are 10.0 s → 5 frames → bit-identical.** A refactor that
   reorders these two operations passes the *entire* golden suite.
2. **It also passes the tolerance gate.** The worst relative deviation is `7.7e-08` against a
   calibrated bound of `1e-4` — roughly **1300× inside**. No existing gate in either repo can see it.
3. **Real tracks are 3–5 minutes → 119+ frames → the divergence is live in production**, on exactly
   the six descriptors vibe-doctor stores.
4. It would silently break bit-identity with the frozen `baseline_v0_1_0` anchor — the property a
   parallel audit stream reported as "24/24 bit-identical". Bit-identity is the assertion that dies;
   the tolerance assertion survives and gives false comfort.

### Binding constraint on the item 1 implementation

> **`mean_over_frames` must continue to execute as `value.mean(axis=0)` on the full output matrix,
> with `take[index]` applied afterwards — exactly the current order in `execute_plan`
> (`python/sonance_extract.py:456-461`). `reduce: :none` takes the column *without* reducing. The two
> paths must not be refactored into a shared "select first, then optionally reduce" form.**

This is counter-intuitive: the shared form is the cleaner code, and it is wrong. The reduction is
defined over the matrix, not over the selected column.

### Gate this, because nothing currently can

The fixtures cannot catch it, so the design must add a gate that can. Required: a spec that asserts
bit-identity of `mean_over_frames` output against a stored value **at a frame count ≥ 39** — i.e. a
fixture of at least ~60 s, which the repo does not currently have. Without that fixture the
constraint above is a comment, not a gate, and the next refactor will quietly violate it.

*(This also refines audit finding F7: the fixtures are not merely short on the sub-3s boundary — they
are short at the top end too, and that blind spot is load-bearing for this design.)*

---

## 1. Two premise corrections, established by execution

Both change what the work actually is. I state them before the designs because they resize items 2
and 1 respectively.

### 1a. Issue #14's premise is mostly wrong: consumer registry extension **already works today**

Issue #14 says the registry "is not merely a default, it is the boundary" and calls this
"architectural lock-in". It is not. At v0.3.0, with no gem change:

```
extended registry ids: 10 (default 9)  includes onset_rate_custom=true
plan.algorithms: [{ref: "a0", name: "RhythmExtractor2013", params: {method: "degara"}, sample_rate: 44100}]
-> consumer extension ALREADY WORKS; Extractor.new(registry:) already accepts it
```

`Registry.new(models:, descriptors:)` is public and validating; `Registry#models` / `#descriptors`
are public readers; `Descriptor` and `Model` are public `Data` types that validate in their own
initializers; and `Extractor.new(registry:)` already accepts a custom registry. A consumer can
compose `Registry.new(models: Registry.default.models, descriptors: Registry.default.descriptors + [mine])`
today and it plans correctly.

**Consequence:** item 2 is not an architectural change. It is documentation, one convenience method,
test coverage of a contract that is currently accidental rather than guaranteed — and one **genuine
gap** that #14 does not mention, in 1b.

### 1b. Ruby does **not** gate standalone algorithm names — containment is single-point today

The security boundary #14 says must survive is thinner than it looks. The Ruby planner forwards
`FromAlgorithm#name` verbatim with no enum check:

```
Ruby planner emitted name="os.system"          <- Ruby does NOT gate standalone names
Ruby planner emitted name="MetadataReader"     <- Ruby does NOT gate standalone names
Ruby planner emitted name="__import__"         <- Ruby does NOT gate standalone names
```

Graph algorithms *are* gated Ruby-side (`Planner#graph_algorithm` uses `GRAPH_ALGORITHMS.fetch` with
a raising default):

```
REJECTED ConfigurationError: unknown graph algorithm: arbitrary_python_thing;
  valid algorithms: tensorflow_predict_musicnn, tensorflow_predict_2d
```

The standalone path has no such mirror. Containment holds today **only** because Python rejects it at
the seam — which it does, correctly:

```
os.system              sonance plan invalid: algorithms[0].name is not allowed: 'os.system'
MetadataReader         sonance plan invalid: algorithms[0].name is not allowed: 'MetadataReader'
__import__             sonance plan invalid: algorithms[0].name is not allowed: '__import__'
RhythmExtractor2013    (accepted — passing control)
```

This is sound but it is **one gate, not two**. That is acceptable while the registry is closed and
every `FromAlgorithm` row is gem-authored. The moment item 2 makes consumer-authored rows a
*documented, supported* path, a single-point containment gate is the wrong posture. Item 2 must
close this, and closing it is the only part of item 2 that is real engineering.

---

## 2. Item 1 — reduction becomes a caller choice (#9)

### Where `reduce` lives

**Ruling: `reduce` moves from `Model` onto `FromModel` — the produced-by edge — and reduction becomes
a property of the *descriptor*, not of the model.**

```ruby
FromModel = Data.define(:model, :select, :reduce)   # reduce defaults to :mean_over_frames
```

`Model#reduction` is removed. Reduction is not a fact about a model — the same model can legitimately
serve a mean-reduced scalar and a frame-wise series in the same run. It is a fact about *what the
caller asked for*, which is exactly what a descriptor is.

This falls out of the existing architecture rather than fighting it:

- `Descriptor#kind` already distinguishes `:scalar` from `:series`.
- `FromModel#select` already lives on the same edge, and is already the "how do I project this
  model's output" knob. `reduce` is its sibling.
- `Planner#graph_models_for` dedupes by **model id**, so requesting `mood_happy_musicnn` (scalar,
  mean) *and* `mood_happy_musicnn_frames` (series, none) together plans **one** graph pair and pays
  **one** inference. The frame-wise variant is nearly free alongside the scalar.

No new argument on `Extractor#analyze`. No per-call flags. **The descriptor is the request.** A caller
who wants frames asks for a descriptor whose `reduce` is `:none`.

### What `reduce: :none` returns

A `Series`. This gives the existing-but-unused `Series` type its first real use — no registry
descriptor is `kind: :series` today, so `Series` is currently dead code exercised only by unit specs.

For a graph output of shape `(n_frames, n_classes)` with `select: {class: "happy"}`:

- `reduce: :mean_over_frames` → `Scalar`, value = `matrix.mean(axis=0)[index]` (**unchanged order**,
  per §0)
- `reduce: :none` → `Series`, `values` = the `n_frames` per-frame values of column `index`

For `embedding_musicnn` (`select: nil`), `reduce: :none` would be a per-frame matrix. **I am not
supporting that shape now** — see §8. `:none` is defined for projected (single-column) graph outputs
only; an unprojected `:none` is rejected at plan validation with a clear message. That keeps `Series`
one-dimensional, which is what its contract already says.

### How `Series` carries the time axis — and where the times come from

This is the part with a trap in it, and it is the second-most important decision in the document.

`Series` requires `times`, and validates `times.length == values.length`. So `reduce: :none` must
produce a time axis. There are three places it could come from, and two of them are wrong:

- **Python computes it** — ✗ **rejected.** Python would need MusiCNN's mel-frontend hop (256 samples
  at 16 kHz) to convert patch indices to seconds. That constant is **not** an algorithm parameter; it
  is a MusiCNN internal. Putting it in `execute_plan` would place a MusiCNN-specific constant on the
  generic executor path — replacing the `mean_over_frames` opinion with a patch-geometry opinion in
  the *same place*. That is the defect #9 exists to remove, reintroduced in a new costume.
- **Ruby computes it from hardcoded constants** — ✗ **rejected**, same reason, worse location.
- **The registry model row declares it** — ✓ **chosen.**

`Model` already carries exactly this class of fact — `sample_rate`, `input_node`, `output_node`,
`classes`, `sha256`, `byte_length` — all pinned, all reviewed, all verified. Frame geometry is the
same kind of fact and belongs in the same place:

```ruby
Model = Data.define(..., :frame_period, :frame_duration)
```

For the six shipped MusiCNN models, both values are **derived from Essentia's declared parameter
defaults and confirmed by execution**:

```
patchHopSize default = 93 mel frames    patchSize default = 187 mel frames
mel frame rate = 16000 / 256 = 62.5 fps
patch start hop = 93 / 62.5 = 1.488000 s     patch duration = 187 / 62.5 = 2.992000 s
```

Frame `k` starts at `k * 1.488` s and spans `2.992` s. Validated against real Essentia at five
durations:

```
file          dur  actual  predicted  match
white_noise  10.0       5          5  OK
t30          30.0      19         19  OK
t60          60.0      39         39  OK
t90          90.0      59         59  OK
track180    180.0     119        119  OK
```

`Series#times` is populated from `frame_period` / `frame_duration` by `AnalysisBuilder` at
construction. `Series` gains one small change: **`times` may be `nil`**, meaning "the producer did not
declare a time axis." That is the honest representation for a future model whose geometry is unknown,
and it is strictly better than fabricating index-as-seconds, which would be a lie with units on it.

### The declared-geometry hazard, and its gate

`patchHopSize = 93`, `patchSize = 187` and mel hop `256` are Essentia **defaults** that the gem never
sets and cannot see from Ruby. If an Essentia release changed a default, the declared `frame_period`
would silently become wrong — and every `Series` would carry a plausible, wrong time axis.

**Required gate (non-vacuous):** a spec that predicts frame count from the declared geometry and
asserts it against real Essentia for a known-duration fixture — the `predicted == actual` table
above, executed rather than recorded. It must fail loudly and name the environment when the
prediction misses. Declaring the geometry without this gate is worse than not declaring it, because a
wrong time axis is harder to notice than an absent one.

### Wire protocol

`reduce` stays **required** on graph emits — the wire stays explicit and the Ruby planner always
writes it. What changes is the accepted set:

```python
_REDUCTIONS = frozenset({"mean_over_frames", "none"})
```

`validate_emits` (`python/sonance_extract.py:258-262`) checks membership in `_REDUCTIONS` instead of
equality with one literal. That is the whole of the validation change for #9: a table lookup
replacing a hardcoded literal — the same shape as the `_ALGORITHM_MINIMUM_SPANS` fix that correctly
resolved the earlier `validate_params` leak.

Defaulting happens in **Ruby**, at the registry, where the caller can see it — not on the wire.

### Does any other reduction earn its place now? No.

`:none` and `:mean_over_frames` are a **complete basis**. Given `:none`, a caller computes max,
median, variance, percentiles, or any windowed statistic in one line of Ruby over `Series#values`.

Adding `:max` or `:variance` would *add* an opinion about which statistics matter, not remove one —
the exact failure mode #9 is about, committed a second time. `mean_over_frames` keeps its place only
because it is the established default for all six shipped heads and removing it would break every
consumer for no gain.

**Deferred, explicitly:** every other reduction. Revisit only when a concrete descriptor needs one
that cannot be computed from `:none` — which, for a pure function of the frame vector, is never.

---

## 3. Item 2 — the registration contract (#14)

Per §1a the mechanism exists. The deliverable is to make it a **guaranteed contract** rather than an
accident of public readers, and to close the containment gap in §1b.

### The contract

```ruby
# Registry.default stays exactly as it is: curated, verified, pinned. Never mutated.
registry = Sonance::Registry.default.with(
  models:      [my_model],        # optional
  descriptors: [my_descriptor]    # optional
)
extractor = Sonance::Extractor.new(models_dir:, registry:)
```

`Registry#with(models: [], descriptors: [])` returns a **new frozen `Registry`** built through the
existing `Registry.new`, so it inherits every current validation with no new code path:

- duplicate model id / descriptor id rejected **across the union**, not just within the addition
- `Model` initializer: bare `.pb` basename, no `..`, HTTPS-only `source_url`, lowercase 64-hex
  `sha256`, positive integer `byte_length`
- `Descriptor` initializer: `range_kind: :hard` ⟹ `native_range == sanity_range`

`Registry.default` is frozen and never mutated — `with` composes, it does not modify. There is no
global registration hook, no `Registry.register!`, no at-exit mutation. **Registration is
constructing a value, not performing a side effect.** That is what makes it safe to reason about.

### The one real change: a Ruby-side standalone-algorithm gate

Closing §1b:

```ruby
class Planner
  GRAPH_ALGORITHMS = { tensorflow_predict_musicnn: "TensorflowPredictMusiCNN",
                       tensorflow_predict_2d:      "TensorflowPredict2D" }.freeze
  STANDALONE_ALGORITHMS = %w[RhythmExtractor2013].freeze     # NEW — mirrors Python's _ALGORITHM_PARAMS
end
```

`Planner#algorithm_plan` validates `definition.name` against `STANDALONE_ALGORITHMS` and raises
`ConfigurationError` otherwise — mirroring what `graph_algorithm` already does for graphs. This is
additive for every legitimate caller (Python's `_ALGORITHM_PARAMS` has exactly one entry, so the two
tables are identical today) and it converts containment from one gate to two.

**Drift gate:** Python already exposes `capabilities()` (`sonance_extract.py:66-70`) returning
`sorted(_GRAPH_ALGORITHMS | _ALGORITHM_PARAMS.keys())`, and the CLI already has `--capabilities`. A
spec asserts `GRAPH_ALGORITHMS.values + STANDALONE_ALGORITHMS == capabilities()["algorithms"]`. The
data source exists; only the assertion is missing. Without it the two enums drift and the Ruby mirror
becomes a lie.

### Proof by construction that registration cannot reach an algorithm outside the enum

Not an assertion — the containment argument is structural, and each link is demonstrated.

A consumer-supplied descriptor influences the subprocess through exactly **two** fields:
`FromModel#model` (a registry symbol) and `FromAlgorithm#name` (a string). Nothing else a consumer
writes becomes a Python identifier. There is **no `getattr`, no `eval`, no `importlib`, and no
string-to-callable step anywhere in `sonance_extract.py`** — algorithm construction is a literal
`if`/`elif` chain over string equality with a raising `else`.

**Graph path — three gates, any one sufficient:**

| # | Gate | Location | Evidence |
|---|---|---|---|
| G1 | `GRAPH_ALGORITHMS.fetch(id)` raising default | Ruby `plan.rb:92-97` | `REJECTED ConfigurationError: unknown graph algorithm: arbitrary_python_thing` |
| G2 | `graph["algorithm"] not in _GRAPH_ALGORITHMS` | Python `sonance_extract.py:155-156` | rejects before construction |
| G3 | `build_pipeline` `if`/`elif`/`else: raise` | Python `sonance_extract.py:391-402` | no dynamic dispatch exists to reach |

**Standalone path — three gates after this design; two today:**

| # | Gate | Location | Evidence |
|---|---|---|---|
| S1 | `STANDALONE_ALGORITHMS` check — **NEW** | Ruby `plan.rb` | closes §1b |
| S2 | `name not in _ALGORITHM_PARAMS` | Python `sonance_extract.py:202-203` | `algorithms[0].name is not allowed: 'os.system'` / `'MetadataReader'` / `'__import__'`; `RhythmExtractor2013` accepted as control |
| S3 | `build_pipeline` `if`/`elif`/`else: raise` | Python `sonance_extract.py:406-412` | no dynamic dispatch exists to reach |

The property that makes this a *proof* rather than a list: **extending the enum requires editing
gem-owned source in two repositories' worth of files and passing the drift gate.** No registry value,
no plan JSON, and no consumer input can add a member. `_ALGORITHM_PARAMS` is a module-level literal;
`_GRAPH_ALGORITHMS` is a module-level `frozenset`; `GRAPH_ALGORITHMS` and `STANDALONE_ALGORITHMS` are
frozen Ruby constants. A consumer registering a descriptor is choosing **from** the enum, never
**adding to** it.

**Untouched, as required:** the parameter whitelist (`_ALGORITHM_PARAMS` types, `_ALGORITHM_PARAM_DOMAINS`
ranges/enums, `_ALGORITHM_MINIMUM_SPANS`), the graph `params` prohibition
(`sonance_extract.py:157-158`), the model host allowlist (`ModelStore::DOWNLOAD_HOST`,
`validate_download_uri!`) and its **per-redirect-hop** re-validation
(`Downloader#request` re-calls `validate_download_uri!` on every hop, `model_store.rb:178-189`), the
`.pb`-basename regex, symlink/`NOFOLLOW` handling, and the SHA-256 + byte-length verification. This
design adds gates and removes none.

**One honest consequence to write down:** a consumer-registered model is fetched from *its own*
`source_url`, and `validate_download_uri!` allows **only** `essentia.upf.edu`. So a consumer may
register a descriptor over an existing pinned model freely, but cannot register a *new model file*
hosted anywhere else. That is a real limit on item 2's usefulness and it is the **correct** limit —
relaxing the host allowlist to make third-party models fetchable is exactly the "weaken a security
control to achieve thinness" failure the brief forbids. Consumers needing a foreign model must place
it in `models_dir` out of band; the SHA-256 gate still governs what is accepted.

### Shipped descriptor set: unchanged

`Registry.default` keeps exactly its nine descriptors. Per the owner's direction — *mechanism now,
set later* — this design adds **zero** descriptors. The frame-wise variants described in §2 are
demonstrated in documentation as consumer-registered examples, not shipped as defaults.

---

## 4. Item 3 — range stops being a veto (#15)

### The current policy is already incoherent, which sharpens the choice

Issue #15 presents the veto as a uniform policy. It is not. Derived from the registry and confirmed
with passing controls:

```
valence_emomusic             range_kind=nominal    native=1.0..9.0   sanity=-3.0..13.0
arousal_emomusic             range_kind=nominal    native=1.0..9.0   sanity=-3.0..13.0
danceability_musicnn         range_kind=hard       native=0.0..1.0   sanity=0.0..1.0
mood_acoustic_musicnn        range_kind=hard       native=0.0..1.0   sanity=0.0..1.0
mood_relaxed_musicnn         range_kind=hard       native=0.0..1.0   sanity=0.0..1.0
mood_happy_musicnn           range_kind=hard       native=0.0..1.0   sanity=0.0..1.0
embedding_musicnn (vector)   range_kind=unbounded  native=nil        sanity=nil
bpm_rhythm2013               range_kind=unbounded  native=nil        sanity=nil
beat_confidence_rhythm2013   range_kind=unbounded  native=nil        sanity=nil

danceability_musicnn  -0.1  -> REJECTED MalformedOutputError: outside sanity range 0.0..1.0
danceability_musicnn   0.5  -> ACCEPTED (0.5)                                    <- control
danceability_musicnn   1.1  -> REJECTED MalformedOutputError
valence_emomusic      -2.9  -> ACCEPTED (-2.9)          <- nominal range is wide; this reaches the app
valence_emomusic      13.1  -> REJECTED MalformedOutputError
bpm_rhythm2013        -5.0  -> ACCEPTED                 <- negative BPM sails through
bpm_rhythm2013         1e9  -> ACCEPTED                 <- so does a billion BPM
embedding_musicnn  all 1e6  -> ACCEPTED (no sanity gate on Vector at all)
```

So the "gem vetoes implausible values" guarantee covers **six of nine descriptors, scalars only**. A
negative BPM is accepted today. The veto is not a safety property the system rests on; it is a
partial, inconsistently applied policy that happens to cover the four softmax heads.

**A correction to #15 and #24 worth recording:** the app's clamp is *not* uniformly dead code. Because
`valence_emomusic` is `:nominal` with sanity `-3.0..13.0`, a value of `-2.9` reaches the mapper,
rescales to `(-2.9 - 1.0) / 8.0 = -0.4875`, and **is clamped by live code**. Only the **four softmax
clamps** are unreachable. That is exactly why #24 reports the two emomusic heads as already covered in
both directions — they are genuinely reachable, and the asymmetry in that spec is not arbitrary.

### Ruling: Option 2 — report, don't veto

**Chosen.** Not option 1 (discards information the gem has and the caller may not). Not option 3.

**Why not option 3 (configurable strictness), which is the tempting one.** It has real appeal: `strict:
true` by default means zero change for vibe-doctor and no sequencing hazard at all. I reject it
because it does not make the decision — it ships both products and makes the opinionated one the
default. Every consumer who never passes the flag keeps the veto forever, so the gem remains a policy
layer by default and becomes a thin binding only for those who opt in. Two semantics behind one API
is a worse permanent artifact than one clearly-versioned breaking change. It also collides with item
2: once consumers register their *own* descriptors with their *own* declared ranges, `strict:` would
have to decide whether the gem enforces a consumer's self-declaration against them — a question that
has no good answer and that option 2 never has to ask.

**What replaces the veto.** Split the two meanings currently conflated in `MalformedOutputError`:

| Condition | Today | After |
|---|---|---|
| non-finite (NaN / ±Inf) | `MalformedOutputError` | **unchanged** — `MalformedOutputError`, a `TrackError` |
| vector length ≠ declared `shape` | `MalformedOutputError` | **unchanged** |
| series `times`/`values` length mismatch | `MalformedOutputError` | **unchanged** |
| wrong type / wrong kind | `SchemaError` (fatal) | **unchanged** |
| **value outside declared range** | `MalformedOutputError` | **reported as state on `Value`** |

That distinction is the whole basis of the ruling: **non-finite output is malformed — genuinely
broken, no caller can use it. Out-of-range output is well-formed but surprising — the caller can
absolutely use it, and only the caller knows whether to.** The first is the binding's business; the
second is policy, and policy belongs to the consumer.

```ruby
value.range_status      # :within | :outside_native | :outside_sanity | :unknown
value.in_declared_range? # false when :outside_native or :outside_sanity
```

`:unknown` is returned when no range is declared — which, per the table above, is the honest answer
for `bpm_rhythm2013`, `beat_confidence_rhythm2013` and `embedding_musicnn` today, and is strictly
more informative than the silent acceptance they get now.

**Field names stay.** `sanity_range` and `range_kind: :hard` keep their names despite `sanity_range`
no longer enforcing anything. Renaming would break every consumer-registered `Descriptor` from item 2
for zero functional gain. `:hard` retains a real meaning — "the producing algorithm guarantees this
range" — which is a useful claim even when unenforced. The semantic change must be documented loudly
in the CHANGELOG and in the `Descriptor` docstring; it must not be left to be discovered.

### What I am giving up, stated plainly

1. **Automatic per-track skip.** Today a wild value skips one track cleanly through
   `Sonance::TrackError`. After this, the gem hands the value over and the consumer must decide. That
   decision does not disappear — it moves, and it must move *deliberately*.
2. **A free gate for consumers who never read `range_status`.** Anyone who upgrades and ignores the
   new API gets values they were previously protected from. This is the real cost, it is not
   theoretical, and the version bump exists to make it visible.
3. **The invariant "a `Scalar`'s value is always inside its declared range."** Some consumer may be
   relying on it implicitly. vibe-doctor is — see §6.

I am **not** giving up the non-finite check, the shape checks, or `MalformedOutputError` itself. A
thin binding still refuses to hand you a `NaN` dressed as a `Float`.

### The second-order effect neither issue names

#15 warns that a skipped track becomes "a `MoodVector` numericality failure at save." **That is only
true if the app's clamp is incomplete** — which is precisely the #24 hazard. With the clamp intact in
both directions, an out-of-range value is clamped to `[0.0, 1.0]` and **saves successfully**.

Which surfaces the effect that actually matters and that neither issue mentions:

> **A track that is skipped today will, after this change, be included with a saturated value.**
> `MoodGroundingService#aggregate` averages per-track coordinates into an album vector. Today a wild
> track is excluded from that average. After this change it contributes a `0.0` or `1.0` extreme.
> Album-level mood vectors will shift, silently, with no error anywhere and no test failing.

This is a data-semantics change disguised as a dependency bump, and it is a stronger argument for
careful sequencing than the save-failure scenario #15 describes. My recommendation for the app is in
§6: **preserve today's behaviour explicitly** — check `range_status`, skip the track. The gem gets
thin; the app's observable behaviour does not change at all. Clean separation, and the app keeps
making the decision it already makes.

---

## 5. Versioning — what breaks, and for whom

Two releases, not one. Items 1+2 are structurally safe; item 3 changes observable behaviour. Bundling
them would make the breaking change unidentifiable and unrevertable in isolation.

### `0.4.0` — items 1 and 2

Breaking (API shape only; **no value changes, no error-behaviour changes**):

| Change | Breaks |
|---|---|
| `Model` loses `:reduction`, gains `:frame_period`, `:frame_duration` | anyone constructing `Model.new(...)` |
| `FromModel` gains `:reduce` (default `:mean_over_frames`) | anyone constructing `FromModel.new(...)` |
| `Series#times` may be `nil` | anyone consuming a `Series` |
| `Planner::STANDALONE_ALGORITHMS` now gates standalone names | anyone registering an algorithm outside the enum — i.e. nobody legitimate |

**Who is actually affected: nobody today.** vibe-doctor constructs neither `Model` nor `FromModel`; it
reads `Registry.default` and its `native_range` only (`config/initializers/sonance_registry.rb`). No
registry descriptor is `kind: :series`, so `Series` has no consumer. And per §0, every existing
descriptor value is **bit-identical** before and after — that is a release-gate requirement, not an
aspiration.

### `0.5.0` — item 3

Breaking, behaviourally, and this is the one that matters:

> **An out-of-range descriptor value no longer raises `Sonance::MalformedOutputError`.** Callers who
> relied on `Sonance::TrackError` to skip such tracks will now receive the value. They must read
> `Value#range_status` and decide.

Affected: **vibe-doctor**, at `mood_grounding_service.rb:116` and `:129`. It is the only known
consumer and it is insulated until it repins.

Both are minor bumps under 0.x semver, where minor signals breaking. Neither is a `1.0.0` candidate:
`1.0.0` should wait until the frame-series API has a real consumer and the shipped descriptor set has
been expanded per the owner's "later", so that 1.0 freezes something that has been exercised.

---

## 6. Landing order across both repos

**The pin is the insulation, and it changes where the hazard actually is.** vibe-doctor pins
`tag: "v0.3.0"`, and Bundler resolves that tag by name — gem releases are invisible to the app until
someone edits the Gemfile. So:

> **#15's ordering requirement is correct in effect but imprecise in mechanism.** It says land #24
> before #15. In truth #15 can land in the gem at any time; the hazard window opens at the **repin
> commit** in vibe-doctor, not at the gem release. Stating it precisely matters, because the imprecise
> version blocks gem work that is not actually blocked.

### Required order

| Step | Where | What | Unguarded if this step is skipped or reordered |
|---|---|---|---|
| **1** | app | **vibe-doctor#24** — `[head × direction]` clamp coverage, both bounds on all four softmax heads | Nothing yet. This is prep, and it is cheap, and it must be first because everything downstream assumes the clamp is trustworthy. |
| **2** | gem | **0.4.0** (items 1+2). Release gate: existing descriptor values bit-identical (§0), frame-geometry gate green, enum drift gate green | Nothing — app is pinned at v0.3.0. |
| **3** | gem | **0.5.0** (item 3). CHANGELOG states the veto removal in the words of §4 | Nothing — app is still pinned. |
| **4** | app | **Explicit range handling**: read `Value#range_status`; on `:outside_native` / `:outside_sanity`, raise into the existing `TrackOmission` path so the track is skipped exactly as today | — |
| **5** | app | **Repin** to `v0.5.0`, in the **same commit as step 4 or later, never earlier** | — |

### What breaks if the order is violated

- **Step 5 before step 4** (repin without range handling) — the real hazard, and it is *silent*. With
  #24 landed the clamp holds, so nothing raises and nothing fails. Instead, tracks that were
  previously skipped are now included with saturated `0.0`/`1.0` values, and
  `MoodGroundingService#aggregate` averages them into the album vector. **Album moods drift with no
  error, no log line, and no failing test.** This is a data-corruption window, not a crash window,
  which makes it far worse than it looks.
- **Step 4 or 5 before step 1** (#24 not landed) — the clamp has one direction per softmax head, so
  half of it can be deleted or refactored away with the app suite green at 298 examples. If the
  missing direction is the one that fires, the unclamped value reaches `MoodVector`, whose
  numericality validation (`0.0..1.0`, the sole storage-level backstop — there is no DB check
  constraint) rejects the save. A skipped track becomes a failed album enrichment: later, quieter, and
  in a different place, exactly as #15 warns.
- **Step 3 before step 1** — **nothing is unguarded.** The pin holds. This is the case #15's phrasing
  wrongly implies is dangerous.

### Should the app repin to 0.4.0 in between? No.

It gains nothing — vibe-doctor consumes no frame series and registers no descriptors. Each repin is a
window; take one, not two. Go from `v0.3.0` straight to `v0.5.0` at step 5.

### One gate worth adding at step 4

`config/initializers/sonance_registry.rb` already asserts at boot that the mapped descriptors exist
and that emomusic native ranges match. Extend it to assert that every mapped descriptor still
declares the range the mapper assumes. After #15 the gem no longer enforces those ranges, so this
initializer becomes the app's own statement of what it requires — and it fails at boot, which is the
loudest and cheapest place to fail.

---

## 7. What I will NOT do, and why

- **Not adding `:max`, `:median`, `:variance`, or percentile reductions.** `:none` plus
  `:mean_over_frames` is a complete basis; every other statistic is one line of Ruby over
  `Series#values`. Adding them would commit the exact error #9 exists to correct — putting an opinion
  about which statistics matter on the universal path.
- **Not shipping additional descriptors.** The owner said mechanism now, set later. Shipping the
  frame-wise variants as defaults would answer a question nobody asked and would expand the pinned,
  verified surface without the verification to match.
- **Not adding a `strict:` flag** (issue #15 option 3). Defended in §4: it ships two products and
  makes the opinionated one the default.
- **Not renaming `sanity_range` or `range_kind`.** Semantics change; names stay. Renaming breaks every
  consumer-registered `Descriptor` from item 2 for zero functional gain.
- **Not relaxing the non-finite check.** `NaN`/`±Inf` stays a `MalformedOutputError`. A thin binding
  refuses to hand you a value that is not a number; that is not an opinion about music.
- **Not having Python compute frame times.** It would require MusiCNN's mel-hop constant in the
  generic executor — the #9 defect reintroduced one layer down.
- **Not supporting `reduce: :none` for unprojected (vector) outputs** — e.g. per-frame
  `embedding_musicnn` as a 2-D matrix. `Series` is one-dimensional by contract and I am not
  introducing a matrix value type speculatively. Plan validation rejects it with a clear message
  until a real consumer needs it.
- **Not weakening the algorithm enum, the parameter whitelist, the graph-`params` prohibition, or the
  model host allowlist and its per-hop redirect validation.** Out of scope by instruction, and
  correct: §3 adds gates and removes none. The host allowlist in particular limits item 2's reach
  (§3, "one honest consequence") and that limit stays.
- **Not fixing audit finding F1** (duplicate `RhythmExtractor2013` instantiation, `plan.rb:100-103`)
  in this design — it is a separate issue. **But flagging the adjacency:** F1's fix changes the
  `FromAlgorithm` dedup key, and item 1 changes `FromModel`'s shape. They touch neighbouring planner
  code and should be sequenced deliberately rather than merged concurrently.
- **Not touching the canonical x86_64 golden gate.** Out of scope here, and §0 makes it *more*
  important, not less: the golden gate cannot see the reordering hazard, so the answer is an
  additional bit-identity gate at a longer duration, not a change to the existing one.

---

## 8. Evidence

All experiments run against real Essentia `2.1-beta6-dev` natively on arm64 with the six registry
models fetched and SHA-256 verified. Both repos read-only; every mutated artifact lives in the
scratchpad.

**§0 — reduce/take reordering** (the load-bearing finding): `mean_then_index` vs `index_then_mean` on
`mood_happy` softmax across 8 durations, table reproduced in §0. 5/19/59 frames bit-identical;
**39 and 119 frames divergent** at rel `6.238e-08` and `7.722e-08`. All committed fixtures are 5
frames.

**§2 — frame geometry**: Essentia-declared defaults `patchHopSize = 93`, `patchSize = 187`,
`lastPatchMode = "discard"`, `batchSize = 64`; mel rate `16000/256 = 62.5 fps`. Predicted vs actual
frame counts match at 10/30/60/90/180 s (5/19/39/59/119). Patch hop `1.488000 s`, patch span
`2.992000 s`.

**§1a — registry extension works at v0.3.0**: composed a 10-descriptor registry from
`Registry.default.models` / `.descriptors` plus a consumer `Descriptor`; planned successfully to
`{ref: "a0", name: "RhythmExtractor2013", params: {method: "degara"}, sample_rate: 44100}`.

**§1b / §3 — containment**: Ruby planner forwards `"os.system"`, `"MetadataReader"`, `"__import__"`
unchecked on the standalone path; Ruby *rejects* an unknown graph algorithm with
`ConfigurationError`; Python rejects all three hostile standalone names with
`sonance plan invalid: algorithms[0].name is not allowed`, and accepts `RhythmExtractor2013` as
control.

**§4 — range policy**: full 9-descriptor range table derived from the registry (not transcribed);
`danceability_musicnn` rejects `-0.1` and `1.1`, accepts `0.5` (control); `valence_emomusic` accepts
`-2.9`; `bpm_rhythm2013` accepts `-5.0` and `1e9`; `embedding_musicnn` accepts all-`1e6`;
`MalformedOutputError < TrackError` is `true`, `SchemaError < FatalError` is `true`.

**Repos untouched**: gem `main` @ `d514137`, app `docs/essentia-gem-v2-design` @ `1f8ad78`; no files
modified, staged, committed, or repinned in either.

---

## Summary

The three issues are genuinely different sizes, and the design says so rather than treating them as
peers. **#9 is real and subtle** — the fix is small, but it sits on top of a floating-point ordering
constraint that no existing gate can see, and getting that wrong would silently shift every
production value. **#14 is mostly already done** — the mechanism works today; what is missing is a
documented contract, a drift gate, and one Ruby-side enum check that closes a single-point
containment gap the issue does not mention. **#15 is the only one with real consumer risk**, and its
danger is not the save failure the issue describes but a silent shift in album aggregates when
previously-skipped tracks start being included with saturated values.

The gem becomes a thin binding on all three axes without a single security control being relaxed:
containment gets *stronger* (two gates on the standalone path where there was one), the host
allowlist stays and deliberately limits what item 2 can reach, and the values the gem returns stay
bit-identical.
