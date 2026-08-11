**SUPERSEDED ROUND-1 DRAFT — DO NOT READ AS CURRENT.**
Kept only because review reports cite its original line numbers and the disposition table diffs against it; original cited lines are shifted by **+4** below this three-line header.
Authoritative design: `docs/superpowers/specs/2026-08-10-essentia-gem-generalization-design.md`.

# Principal design — ESSENTIA-GEM-V2

Ticket: ESSENTIA-GEM-V2 — generalize `mood_probe` into an unopinionated Essentia gem; refactor
vibe-doctor to consume a subset.
Role: Principal Engineer (Keystone). Pre-implementation architecture pass. **Design only — no code
written, no files in either repo touched.**
Date: 2026-08-10

| Repo | HEAD at time of reading |
| --- | --- |
| vibe-doctor (`/Users/lukeolson/projects/vibe-doctor`) | `0499d9cd38e7009eccbc6f75e50e93bd4800bc3e` |
| mood_probe (`/Users/lukeolson/projects/gems/mood_probe`) | `5360f8fd8609eae39edb5dfab8a07f6439a0b137` |

Scope covered here: open questions **1, 2, 3, 7** plus the type hierarchy and the planner.
Open question 4 (vibe-doctor persistence/aggregation) and 6 (backfill) are touched only where they
constrain sequencing. Open question 5 (model distribution) belongs to the Security Reviewer.

**Verdict on the brief: APPROVE-WITH-CHANGES.** The five settled decisions are sound and I am
designing to them. One correction to the *premise* of decision 2 and one factual correction to
decision 4 are in the CHALLENGE section (§8) — neither changes the direction, both change what gets
built.

Proposed spec filename: **`docs/superpowers/specs/2026-08-10-essentia-gem-generalization-design.md`**

---

## 0. The finding that shapes everything else

I fetched the per-model metadata JSON for every MSD-MusiCNN head in the Tier 0/Tier 1 set. **The
class order is not consistent across heads**, and there is no rule that predicts it:

| Descriptor | Upstream `classes` (output-index order) | Index of the "positive" class |
| --- | --- | --- |
| `danceability` | `["danceable", "not_danceable"]` | 0 |
| `mood_acoustic` | `["acoustic", "non_acoustic"]` | 0 |
| `mood_happy` | `["happy", "non_happy"]` | 0 |
| `mood_aggressive` | `["aggressive", "not_aggressive"]` | 0 |
| `mood_electronic` | `["electronic", "non_electronic"]` | 0 |
| **`mood_relaxed`** | **`["non_relaxed", "relaxed"]`** | **1** |
| **`mood_sad`** | **`["non_sad", "sad"]`** | **1** |
| **`mood_party`** | **`["non_party", "party"]`** | **1** |
| **`voice_instrumental`** | **`["instrumental", "voice"]`** | **no "positive" class exists** |

Two consequences.

**(a) The current gem is correct, and got there by hand.** `ModelRegistry::MODELS`
(`lib/mood_probe/model_registry.rb:12-60`) carries `positive_index: 1` for `mood_relaxed`
(`:39`) and `0` for the other three classification heads (`:23`, `:31`, `:47`). That matches
upstream exactly. It is right, and nothing in the code records *why* — the number 1 is unexplained.

**(b) `positive_index` is the wrong abstraction and must not be carried into the new registry.**
Of the five Tier-1 heads the brief proposes, **three** (`mood_sad`, `mood_party`,
`voice_instrumental`) would ship an inverted or meaningless probability under an index-based
registry filled in by pattern-matching on the existing rows. `voice_instrumental` is the proof: it
has no positive/negative axis at all, so no value of `positive_index` is correct.

**The registry must carry the upstream `classes` array verbatim, and a descriptor must select its
scalar projection by class *name*.** This costs nothing now and is the difference between Phase B
being a data-only change and Phase B being a silent-correctness incident. Every other decision in
this document is downstream of it.

Also verified and worth recording, because it affects the provenance field:

- `msd-musicnn-1.pb` output `model/dense/BiasAdd` has shape **`[1, 200]`** — the embedding is
  **200-d**. Confirmed independently by every head's input schema (`model/Placeholder`, shape
  `[200]`). The gem's `output_node` (`model_registry.rb:16`) is correct.
- Upstream metadata `version` for every classification head is **`"2"`**, while the filename says
  `-1`. The filename suffix tracks the embedding/architecture revision; the metadata `version`
  tracks the head. **Provenance must record both** — recording only the filename loses the head
  revision, recording only `version` loses which embedding it was trained against.
- `emomusic-msd-musicnn-2.json` declares `classes: ["valence", "arousal"]`, output
  `model/Identity`, version `2`. **It does not declare a numeric output range.** `models.html`
  states `[1, 9]`; the authoritative per-model JSON does not. See §1.4 and Risk 5.

---

## 1. Registry entry shape (open question 1a)

### 1.1 Split the manifest in two

The single `Model` struct today (`model_registry.rb:3-10`) conflates two different things: *an
artifact you download and verify* and *a value a consumer asks for*. They have different
cardinality — one `.pb` can back several descriptors (`voice_instrumental` naturally yields both
`voice` and `instrumental`; `emomusic` yields two), and a descriptor can have no `.pb` at all (every
DSP algorithm). Keeping them fused is what forces `positive_index` onto the artifact row, where it
does not belong.

```
Model      — one row per downloadable .pb. Owns: filename, sha256, source_url, graph nodes,
             upstream `classes`, versions, sample rate, and which embedding it consumes.
Descriptor — one row per thing a consumer can request. Owns: id, kind, native range + units,
             and a pointer to how it is produced (a Model projection, or a DSP algorithm).
```

`ModelStore` (`lib/mood_probe/model_store.rb:41-50`) keeps working unchanged against `Model` rows —
it only ever reads `filename`, `sha256`, `source_url`. That is a deliberate no-op: the existing
checksum/fetch machinery is good and this split does not disturb it.

### 1.2 The literal Ruby

Ruby 4.0.1, so `Data.define` — immutable by construction, which matches CLAUDE.md's "prefer
immutable constants" and removes the `.each(&:freeze).freeze` ceremony at `model_registry.rb:60`.

```ruby
module MoodProbe
  # ---- artifact rows -------------------------------------------------------

  Model = Data.define(
    :id,             # :mood_happy_msd_musicnn_1
    :filename,       # "mood_happy-msd-musicnn-1.pb"
    :sha256,
    :source_url,
    :model_version,  # upstream metadata "version" — "2" for the heads, "1" for the embedding
    :framework,      # "tensorflow-2.4.0"
    :sample_rate,    # 16_000 — the rate the graph was trained at; drives the audio plan
    :algorithm,      # :tensorflow_predict_musicnn | :tensorflow_predict_2d
    :input_node,     # "model/Placeholder"
    :output_node,    # "model/Softmax" | "model/Identity" | "model/dense/BiasAdd"
    :classes,        # upstream `classes` VERBATIM, in output-index order. Frozen. nil only if upstream omits it.
    :reduction,      # :mean_over_frames — the gem's declared time-axis collapse (see §8.1)
    :embedding       # id of the Model whose output feeds this one; nil for embedding models themselves
  )

  # ---- how a descriptor is produced ---------------------------------------

  # A projection of a Model's output. `select:` is by CLASS NAME, never by index.
  FromModel = Data.define(
    :model,          # Model#id
    :select          # { class: "happy" } | { output: :valence } | nil (whole output => Vector/Categorical)
  )

  # A native Essentia DSP algorithm. No .pb, no embedding, its own audio sample rate.
  FromAlgorithm = Data.define(
    :name,           # "RhythmExtractor2013"
    :output,         # "bpm" — the algorithm's named output port
    :params,         # { method: "multifeature" }
    :sample_rate     # 44_100
  )

  # ---- consumer-facing rows ------------------------------------------------

  Descriptor = Data.define(
    :id,             # :mood_happy
    :kind,           # :scalar | :categorical | :vector | :series
    :produced_by,    # FromModel | FromAlgorithm
    :native_range,   # Range, or nil
    :range_kind,     # :hard (bounded by construction — gem asserts)
                     # :nominal (documented scale, not enforced by the model — gem does NOT assert)
                     # :unbounded (gem checks finiteness only)
    :units,          # :probability | :bpm | :lufs | :lu | :seconds | :unitless | nil
    :shape,          # Integer for :vector (200), nil otherwise
    :notes           # human-readable; carries UNVERIFIED markers
  )
end
```

`range_kind` is the field that makes settled decision 2 safe, and it is doing more work than
`native_range` alone. Today `Features` applies a single blanket sanity window `-0.5..1.5`
(`lib/mood_probe/features.rb:6`, `:44-52`) to all six heads, which is only meaningful because all
six happen to be on a 0–1 scale. That constant cannot survive contact with BPM or LUFS.
`range_kind` replaces it with a per-descriptor rule:

- `:hard` → the gem **asserts** the value is inside `native_range` and raises `MalformedOutputError`
  otherwise. This is contract validation of a graph that is bounded by construction, not
  normalization, so it does not violate decision 2. It is how a corrupted softmax graph gets caught.
- `:nominal` → the gem asserts **finiteness only**. emomusic lives here. Its declared `1.0..9.0` is
  documentation for the consumer's rescale, not a bound the model honours.
- `:unbounded` → finiteness only. BPM, embeddings.

### 1.3 Row: an existing head (`mood_happy`) — Scalar

```ruby
Model.new(
  id: :mood_happy_msd_musicnn_1,
  filename: "mood_happy-msd-musicnn-1.pb",
  sha256: "d7382bc60304ea4578c298222968cd8d600c31252c7bf3e90b1f728ebb3ec36d",
  source_url: "https://essentia.upf.edu/models/classification-heads/mood_happy/" \
              "mood_happy-msd-musicnn-1.pb",
  model_version: "2",                    # VERIFIED: upstream JSON "version": "2"
  framework: "tensorflow-2.4.0",         # VERIFIED: upstream JSON framework_version
  sample_rate: 16_000,                   # VERIFIED: upstream JSON inference.sample_rate
  algorithm: :tensorflow_predict_2d,     # VERIFIED: upstream JSON inference.algorithm
  input_node: "model/Placeholder",       # VERIFIED: schema.inputs[0].name, shape [200]
  output_node: "model/Softmax",          # VERIFIED: schema.outputs[0], shape [2], op Softmax
  classes: %w[happy non_happy].freeze,   # VERIFIED verbatim
  reduction: :mean_over_frames,
  embedding: :msd_musicnn_1              # VERIFIED: upstream JSON inference.embedding_model
)

Descriptor.new(
  id: :mood_happy,
  kind: :scalar,
  produced_by: FromModel.new(model: :mood_happy_msd_musicnn_1, select: { class: "happy" }),
  native_range: (0.0..1.0),
  range_kind: :hard,                     # softmax — bounded by construction
  units: :probability,
  shape: nil,
  notes: "Frame-wise softmax probability of class \"happy\", mean-reduced over frames."
)
```

`sha256` is carried over from `model_registry.rb:48`; I did not re-verify the digests against
upstream (they are the Security Reviewer's territory, and they are already pinned and enforced by
`ModelStore#verify_model!`, `model_store.rb:56-62`).

The two-line proof that the class-name projection matters — the same shape for `mood_relaxed`:

```ruby
  classes: %w[non_relaxed relaxed].freeze,                                  # VERIFIED — inverted
  produced_by: FromModel.new(model: :mood_relaxed_..., select: { class: "relaxed" })
```

The descriptor row is now *identical in form* to `mood_happy` and the inversion is confined to the
artifact row, where it is a transcription of upstream fact rather than a magic number. Compare
`model_registry.rb:39` (`positive_index: 1`), which is the same information with the reasoning
deleted.

And `voice_instrumental`, which has no positive class — this is the row that cannot be expressed at
all under `positive_index`:

```ruby
  classes: %w[instrumental voice].freeze,                                   # VERIFIED
  # two descriptors, one model, no privileged class:
  Descriptor.new(id: :voice, kind: :scalar,
                 produced_by: FromModel.new(model: :voice_instrumental_..., select: { class: "voice" }),
                 native_range: (0.0..1.0), range_kind: :hard, units: :probability, shape: nil, notes: "...")
  Descriptor.new(id: :instrumental, kind: :scalar,
                 produced_by: FromModel.new(model: :voice_instrumental_..., select: { class: "instrumental" }),
                 native_range: (0.0..1.0), range_kind: :hard, units: :probability, shape: nil, notes: "...")
```

### 1.4 Row: a Tier-2 DSP algorithm (`bpm` via RhythmExtractor2013) — Scalar

```ruby
Descriptor.new(
  id: :bpm,
  kind: :scalar,
  produced_by: FromAlgorithm.new(
    name: "RhythmExtractor2013",
    output: "bpm",                       # VERIFIED: reference lists outputs bpm, ticks, confidence,
                                         #           estimates, bpmIntervals
    params: { method: "multifeature" }.freeze,
    sample_rate: 44_100                  # UNVERIFIED — see notes and Risk 1
  ),
  native_range: nil,
  range_kind: :unbounded,
  units: :bpm,                           # VERIFIED: reference gives unit "bpm"
  shape: nil,
  notes: "UNVERIFIED: the sample rate RhythmExtractor2013 must run at. The Essentia reference " \
         "page does not state a required input rate; 44100 is the conventional default. If it is " \
         "acceptable at 16 kHz the planner loads audio exactly once (see §3.4). MUST be settled by " \
         "measurement in the amd64 image before Phase C."
)

Descriptor.new(
  id: :beat_confidence,
  kind: :scalar,
  produced_by: FromAlgorithm.new(name: "RhythmExtractor2013", output: "confidence",
                                 params: { method: "multifeature" }.freeze, sample_rate: 44_100),
  native_range: nil,
  range_kind: :unbounded,
  units: :unitless,
  shape: nil,
  notes: "UNVERIFIED RANGE. A web search attributed a 0..5.32 range to the multifeature method, " \
         "but neither reference/std_RhythmExtractor2013.html nor tutorial_rhythm_beatdetection.html " \
         "states it — the tutorial only shows an example value of 3.944. Declared :unbounded until " \
         "confirmed against the Essentia source. VERIFIED: with method 'degara' this output is " \
         "always 0, so the params above are load-bearing, not cosmetic."
)
```

`ticks` (VERIFIED: `vector_real`, unit seconds) is the natural first `:series` descriptor. It gets a
`kind` in the hierarchy and **no registry row** — see §2.5.

Note that one algorithm invocation feeds several descriptors. The planner must dedupe on
`(name, params, sample_rate)`, not on descriptor id, or requesting `[:bpm, :beat_confidence]` runs
RhythmExtractor2013 twice. §3.

### 1.5 Row: a Vector (MusiCNN embedding)

```ruby
Model.new(
  id: :msd_musicnn_1,
  filename: "msd-musicnn-1.pb",
  sha256: "cdea0722bcee7f731286843f2233e3aa69887bb5c3e2dce011eff55f38d04f3e",
  source_url: "https://essentia.upf.edu/models/feature-extractors/musicnn/msd-musicnn-1.pb",
  model_version: "1",                    # VERIFIED: upstream JSON "version": "1"
  framework: "tensorflow",               # UNVERIFIED: framework_version not returned in my fetch
  sample_rate: 16_000,                   # VERIFIED: inference.sample_rate
  algorithm: :tensorflow_predict_musicnn,# VERIFIED: inference.algorithm
  input_node: nil,                       # UNVERIFIED: not returned in my fetch; not needed —
                                         #   TensorflowPredictMusiCNN takes audio, not a named tensor
  output_node: "model/dense/BiasAdd",    # VERIFIED: schema.outputs, shape [1, 200], "embeddings"
  classes: nil,
  reduction: :mean_over_frames,
  embedding: nil                         # this IS the embedding
)

Descriptor.new(
  id: :musicnn_embedding,
  kind: :vector,
  produced_by: FromModel.new(model: :msd_musicnn_1, select: nil),   # nil => whole output
  native_range: nil,
  range_kind: :unbounded,                # penultimate dense layer, pre-activation
  units: nil,
  shape: 200,                            # VERIFIED: schema.outputs "model/dense/BiasAdd" shape [1, 200]
  notes: "Penultimate-layer embedding. Also available: model/Sigmoid [1,50] predictions and " \
         "model/dense_1/BiasAdd [1,50] logits (both VERIFIED present in upstream schema, neither " \
         "exposed as a descriptor today)."
)
```

### 1.6 How a head declares its dependency on an embedding

**On the `Model` row, via `embedding:` pointing at another `Model#id`.** Not on the descriptor.

This mirrors upstream exactly — every head's JSON carries an `inference.embedding_model` block
naming `msd-musicnn-1` (VERIFIED for `mood_happy` and `danceability`; the same block is present on
all heads). Transcribing upstream's own dependency edge means the manifest is a *transcription*, not
an interpretation, and a future head on a different embedding (e.g. Discogs-EffNet, Tier 4) is a
data change with no code change.

It belongs on the artifact row rather than the descriptor row because the dependency is a property
of the graph, not of the projection: `:voice` and `:instrumental` are two descriptors that share one
model and therefore share one embedding dependency. Putting `embedding:` on the descriptor would
duplicate it and let the two rows disagree.

The planner then resolves dependencies by walking `descriptor → produced_by.model → model.embedding`
transitively. One level today; the structure supports more without change.

---

## 2. `analyze` signature and the Result/Descriptor types (open question 1b)

### 2.1 Public surface

```ruby
extractor = MoodProbe::Extractor.new(
  models_dir:,                      # unchanged (extractor.rb:6)
  timeout_per_file: 60,             # unchanged (extractor.rb:7)
  python_executable: "python3",     # unchanged (extractor.rb:8)
  backend: nil,                     # unchanged (extractor.rb:9)
  registry: MoodProbe::Registry.default   # NEW — pure injection at the composition root
)

extractor.verify!(descriptors: [...])            # => true; preflights only what the set needs
extractor.analyze(path, descriptors:)            # => MoodProbe::Analysis   (raises on error)
extractor.analyze_all(paths, descriptors:)       # => Array<MoodProbe::Result>
extractor.plan_for(descriptors:)                 # => MoodProbe::Plan   (pure; no subprocess)
```

`descriptors:` is a **required keyword with no default**. A default of "the current six" would
re-privilege them and reintroduce exactly the coupling this work removes; a default of "everything"
would make `analyze(path)` fetch and run every model in the manifest. Required-and-explicit is the
only defensible choice, and it also makes the breaking change loud at every call site instead of
silent.

`registry:` is injected rather than read from a global inside the constructor. This is the
composition-root discipline: `Registry.default` is named **once**, in a default argument, and every
other layer receives what it was given. A consumer that registers custom extractors builds its own
registry and passes it — no global mutation, no test-order coupling, and `plan_for` stays a pure
function of `(registry, descriptors)`.

### 2.2 What comes back

`Result` (`lib/mood_probe/result.rb:4-20`) is a good envelope and survives structurally: `#path`,
`#ok?`, `#error`, positional alignment with the input array. The `#features` reader becomes
`#analysis`. Everything the prior review pinned about `analyze_all` — same length, 1:1 order,
per-file failures never raise, environment failures raise before any file is touched — is unchanged
and must stay in the spec suite.

```ruby
module MoodProbe
  # Keyed collection of typed values for one file.
  class Analysis
    def [](id)      # => Value subclass; raises KeyError on an unrequested id
    def fetch(id)
    def key?(id)
    def keys        # => the requested descriptor ids, in request order
    def each        # Enumerable
    def to_h        # => { id => Value }
  end

  # Where the value came from. Split deliberately: `declared` is re-attached Ruby-side from the
  # registry; `observed` is the only part Python reports. See §4.3.
  Provenance = Data.define(
    :source,          # :model | :algorithm
    :model_filename,  # "mood_happy-msd-musicnn-1.pb" | nil
    :model_version,   # "2" | nil
    :model_sha256,    # | nil
    :algorithm,       # "TensorflowPredict2D" | "RhythmExtractor2013"
    :reduction,       # :mean_over_frames | nil
    :essentia_version,# observed at runtime, e.g. "2.1-beta6-dev1389"
    :gem_version      # MoodProbe::VERSION
  )

  class Value
    attr_reader :descriptor, :provenance
    def id           = descriptor.id
    def kind         = descriptor.kind
    def native_range = descriptor.native_range
    def range_kind   = descriptor.range_kind
    def units        = descriptor.units
  end

  class Scalar < Value
    attr_reader :value            # Float
  end

  class Categorical < Value
    attr_reader :label            # "C" / "major" / "voice"
    attr_reader :strength         # Float or nil — a confidence if the algorithm reports one
    attr_reader :distribution     # { "happy" => 0.83, "non_happy" => 0.17 } or nil (see Risk 8)
  end

  class Vector < Value
    attr_reader :values           # Array<Float>, length == descriptor.shape
  end

  # DEFINED, NEVER CONSTRUCTED IN PHASE A–E. No registry row has kind: :series.
  class Series < Value
    attr_reader :times            # Array<Float>, seconds
    attr_reader :values           # Array<Float>, parallel to times
  end
end
```

### 2.3 How a consumer reads a value and discovers the native range

```ruby
analysis = extractor.analyze(path, descriptors: %i[mood_happy valence_emomusic bpm])

analysis[:mood_happy].value          # => 0.8312...
analysis[:mood_happy].native_range   # => 0.0..1.0
analysis[:mood_happy].range_kind     # => :hard
analysis[:mood_happy].units          # => :probability

analysis[:valence_emomusic].value        # => 4.19...   NATIVE. Not rescaled. Not clamped.
analysis[:valence_emomusic].native_range # => 1.0..9.0
analysis[:valence_emomusic].range_kind   # => :nominal   <- "documented, not enforced"
analysis[:valence_emomusic].provenance.model_version   # => "2"

analysis[:bpm].value                 # => 118.24
analysis[:bpm].units                 # => :bpm
analysis[:bpm].native_range          # => nil
```

Range discovery works **without running anything** as well, which is what a consumer needs to write
a mapper and its specs on a Mac that cannot execute Essentia:

```ruby
MoodProbe::Registry.default.fetch(:valence_emomusic).native_range   # => 1.0..9.0
MoodProbe::Registry.default.descriptors                             # => Array<Descriptor>
MoodProbe::Registry.default.ids                                     # => [:mood_happy, ...]
```

That offline-readability is the concrete thing that makes deferring the normalizer safe, and it is
worth stating as a requirement rather than a side effect: **the registry must be loadable and fully
introspectable with no Python, no models dir, and no Essentia present.** A spec should assert it.

### 2.4 Runtime custom-extractor registration

```ruby
registry = MoodProbe::Registry.new(base: MoodProbe::Registry.default)

registry.add_model(
  MoodProbe::Model.new(id: :approachability_msd_musicnn_1, filename: "...", sha256: "...", ...)
)

registry.add_descriptor(
  MoodProbe::Descriptor.new(
    id: :approachability,
    kind: :scalar,
    produced_by: MoodProbe::FromModel.new(model: :approachability_msd_musicnn_1,
                                          select: { class: "approachable" }),
    native_range: (0.0..1.0), range_kind: :hard, units: :probability, shape: nil, notes: ""
  )
)

# A pure-DSP addition needs no model row and no download at all:
registry.add_descriptor(
  MoodProbe::Descriptor.new(
    id: :bpm_degara,
    kind: :scalar,
    produced_by: MoodProbe::FromAlgorithm.new(name: "RhythmExtractor2013", output: "bpm",
                                              params: { method: "degara" }.freeze, sample_rate: 44_100),
    native_range: nil, range_kind: :unbounded, units: :bpm, shape: nil, notes: ""
  )
)

extractor = MoodProbe::Extractor.new(models_dir:, registry:)
extractor.analyze(path, descriptors: %i[approachability bpm_degara])
```

Rules that make this safe rather than a foot-gun:

1. `Registry.new(base:)` **copies**; `Registry.default` is never mutated. No global state, no
   test-order coupling.
2. `add_descriptor` raises on a duplicate id and on a `produced_by.model` that is not in the
   registry. Fail at registration, not at inference.
3. A registry is **frozen when passed to an `Extractor`**. `plan_for` must be a pure function of
   `(registry, descriptors)`; a registry that can change under a running extractor breaks that.
4. Custom `Model` rows still require `sha256` — `ModelStore#verify_model!`
   (`model_store.rb:56-62`) is unconditional and must stay that way. Registering a custom head is
   not a route around checksum verification.

### 2.5 `Series` — what "define but do not implement" should mean

The value of defining `Series` now is **not** the class. It is that `Analysis#[]` returns a
polymorphic `Value` from day one, so a consumer that writes `analysis[:bpm].value` is already
writing against a type-dispatched API rather than a flat float map. That is the property that lets
beat grids slot in later, and it is delivered by `Analysis` + `Value`, not by `Series`.

So: ship the `Series` class (~10 lines), ship **zero** registry rows with `kind: :series`, and add a
spec asserting `Registry.default.descriptors.none? { it.kind == :series }`. That spec is the thing
that stops the type quietly acquiring an implementation nobody agreed to. `RhythmExtractor2013#ticks`
and `LoudnessEBUR128#momentaryLoudness`/`#shortTermLoudness` (VERIFIED: both `vector_real`) are the
obvious first candidates when the time comes.

---

## 3. The extraction planner (open question 1c) — the most consequential decision

### 3.1 Where it lives: **Ruby, entirely. Python receives a fully-resolved plan and executes it.**

The three options are (a) Ruby plans, Python executes; (b) Python plans from a replicated manifest;
(c) split. I recommend **(a)**, and the argument is not aesthetic:

**1. The registry is Ruby-authored, so Python cannot plan without being sent it anyway.** Settled
decision 1 makes runtime custom registration a Ruby API (§2.4). A Python-side planner would need the
whole manifest — including consumer-registered rows — pushed across the boundary on every call.
Once you are already shipping a document across the seam, shipping the *resolved plan* instead of
the *manifest* is strictly less data, strictly less Python logic, and removes the duplication
question entirely.

**2. This is the decisive one: `essentia-tensorflow==2.1b6.dev1389` has no arm64/macOS wheel**
(`Dockerfile.essentia:8`; the gem README says so in its own words). Python logic in this project is
testable **only inside an amd64 container**. The planner is the most logic-dense new component in
the design — dependency resolution, deduplication, ordering, sample-rate grouping — and it is pure
computation with no Essentia dependency whatsoever. Putting it in Ruby moves it into the one test
environment that runs on every developer's machine and in ordinary CI, with no Docker and no models
dir. Putting it in Python puts the highest-risk logic in the least-testable place. That trade is not
close.

**3. It preserves the "fail before touching a file" property.** An unknown descriptor id, a
descriptor whose model row is missing, a `.pb` absent from the models dir — all become a
`ConfigurationError` raised from `plan_for`/`verify!` **before any subprocess is spawned**. That is
the property `verify!` already provides (`lib/mood_probe/backends/essentia_python.rb:89-101`,
called from `enrich_album_job.rb:8` and `enrichment.rake:19,44`) and the prior review made binding.
A Python-side planner necessarily discovers these faults after the interpreter has started, inside
the timeout budget, with the error surfacing as an exit-2 string.

**4. It keeps Python thin, which keeps the error taxonomy narrow.** Every branch added to
`mood_probe_extract.py` is a branch that can fail in a way the three-member taxonomy
(`unreadable_audio` / `inference_error` / `malformed_output`) does not describe.

The one honest cost: a plan is now a wire artifact with its own schema, and the Ruby planner can
emit a plan Python does not understand. §4.4 pins that.

### 3.2 The Plan object

```ruby
Plan = Data.define(
  :schema_version, # Integer. Bumped on any wire change. Python rejects an unknown value.
  :loads,          # [{ sample_rate: 16_000 }, ...]  — one audio decode per DISTINCT rate
  :graphs,         # ordered; embeddings first, then heads
                   # [{ ref: "emb0", file: "msd-musicnn-1.pb", algorithm: "TensorflowPredictMusiCNN",
                   #    output: "model/dense/BiasAdd", sample_rate: 16_000, input: { audio: 16_000 } },
                   #  { ref: "h0", file: "mood_happy-msd-musicnn-1.pb", algorithm: "TensorflowPredict2D",
                   #    output: "model/Softmax", input: { graph: "emb0" } }]
  :algorithms,     # deduped on (name, params, sample_rate)
                   # [{ ref: "a0", name: "RhythmExtractor2013", params: {...}, sample_rate: 44_100 }]
  :emit            # what to pull out and under which descriptor id
                   # [{ id: "mood_happy", kind: "scalar", from: "h0", take: { index: 0 } },
                   #  { id: "bpm",        kind: "scalar", from: "a0", take: { output: "bpm" } }]
)
```

Note `take: { index: 0 }` in the **plan**, while the **registry** says `select: { class: "happy" }`.
That is intentional: the class-name→index resolution happens in Ruby, against the registry's
`classes` array, and Python never learns what a class name is. Python indexes a tensor; Ruby owns
the semantics. This is the same anti-drift principle as §4.3 — the boundary carries positions, the
Ruby side carries meaning.

### 3.3 Algorithm

```
plan_for(descriptors):
  1. rows        = descriptors.map { registry.fetch!(it) }        # raises on unknown id
  2. models      = rows.filter_map { it.produced_by.model }.uniq   # heads actually requested
  3. embeddings  = models.filter_map { registry.model(it).embedding }.uniq   # transitive closure
  4. graphs      = (embeddings + models).uniq                      # embeddings FIRST, deduped
  5. algorithms  = rows.filter_map { it.produced_by if FromAlgorithm }
                       .uniq_by { [name, params, sample_rate] }     # <- dedupes bpm + beat_confidence
  6. loads       = (graphs.map(&:sample_rate) + algorithms.map(&:sample_rate)).uniq
  7. emit        = rows.map { resolve class name -> tensor index against registry `classes` }
  8. verify every graph file exists in models_dir and matches its sha256   # ConfigurationError here
```

Step 4's `.uniq` is the whole of "each needed embedding computed exactly once": twelve MusiCNN heads
in one request produce **one** `emb0` entry, and every head's `input: { graph: "emb0" }` points at
it. Step 5's `uniq_by` is the equivalent for DSP passes. Step 3's `filter_map` is the whole of "a
consumer that only wants BPM must not pay for MusiCNN" — if no requested descriptor is a
`FromModel`, `models` is empty, so `embeddings` is empty, so `graphs` is empty.

### 3.4 Worked example — `analyze(path, descriptors: [:bpm])` does not run MusiCNN

```
1. rows       = [Descriptor(:bpm, produced_by: FromAlgorithm("RhythmExtractor2013", "bpm",
                                                             {method: "multifeature"}, 44_100))]
2. models     = []          # filter_map over produced_by.model — FromAlgorithm has no #model
3. embeddings = []          # nothing to walk
4. graphs     = []          # <-- MusiCNN is not in the plan
5. algorithms = [{ ref: "a0", name: "RhythmExtractor2013", params: {...}, sample_rate: 44_100 }]
6. loads      = [{ sample_rate: 44_100 }]
7. emit       = [{ id: "bpm", kind: "scalar", from: "a0", take: { output: "bpm" } }]
8. verify     = no graph files required -> models_dir may be EMPTY and this still succeeds
```

Emitted plan:

```json
{"schema_version":1,
 "loads":[{"sample_rate":44100}],
 "graphs":[],
 "algorithms":[{"ref":"a0","name":"RhythmExtractor2013",
                "params":{"method":"multifeature"},"sample_rate":44100}],
 "emit":[{"id":"bpm","kind":"scalar","from":"a0","take":{"output":"bpm"}}]}
```

`"graphs":[]` is the proof at the Ruby layer. Python's model loader iterates `plan["graphs"]`, so
`TensorflowPredictMusiCNN` is never constructed and `msd-musicnn-1.pb` is never opened.

**Three assertions, so the claim is tested and not merely argued:**

1. **Ruby, no Python, runs on a Mac:** `expect(extractor.plan_for(descriptors: [:bpm]).graphs).to be_empty`.
2. **Python, against the existing test double, runs on a Mac:** the fake Essentia double already has
   the right shape — `TensorflowPredictMusiCNN.__init__` at
   `spec/support/fake_essentia/essentia/standard.py:26-29` is a constructor the double controls.
   Extend it to record constructions in a file keyed by `MOOD_PROBE_FAKE_TRACE`, and assert the
   trace is empty after a `[:bpm]` run and contains exactly one MusiCNN entry after a
   `[:mood_happy, :mood_sad]` run. **The "exactly one" case is the more valuable assertion** — it is
   the direct test of embedding reuse, which nothing else covers.
3. **Real Essentia, amd64 image, the honest one:** run `[:bpm]` with a **deliberately empty models
   dir** and assert it succeeds. Nothing can fake that; if any `.pb` were required the run would
   fail at `ModelStore#verify!` (`model_store.rb:41-44`). This is the strongest available proof and
   it costs one spec.

Contrast case, for the record — `descriptors: [:mood_happy, :mood_sad, :bpm]`:

```
graphs     = [emb0=msd-musicnn-1, h0=mood_happy, h1=mood_sad]   # ONE embedding, two heads
algorithms = [a0=RhythmExtractor2013]
loads      = [16_000, 44_100]                                    # TWO decodes — see §8.2
```

---

## 4. Python-side generalization (open question 3)

### 4.1 Shape of the new script

`mood_probe_extract.py` loses `_EMBEDDING_MODEL_FILENAME`, `_HEAD_MODELS`, `_HEAD_OUTPUT_NODE`,
`_VALENCE_AROUSAL_MODEL_FILENAME`, `_VALENCE_AROUSAL_OUTPUT_NODE` (`:10-20`) — every hardcoded
descriptor constant — and gains one input: the plan.

```
python3 mood_probe_extract.py <audio...> --models-dir DIR --plan-json '<json>' [--verify]
```

**Pass the plan as an argv string, not on stdin.** `CommandRunner#capture`
(`backends/essentia_python.rb:31-47`) closes stdin immediately (`:32`) and reads stdout/stderr on
two dedicated threads. Writing a plan to stdin while concurrently draining two pipes is precisely
the deadlock that design exists to avoid, and reworking it would put the timeout/termination path
(`:36-44`, `:63-71`) — the most carefully built code in the gem — back into play for no benefit. A
resolved plan for a realistic request is a few KB against a Linux `ARG_MAX` of ~2 MB. Add a guard:
above 64 KB, spill to a temp file and pass `--plan-file`, with the gem owning cleanup in an
`ensure`. The guard will not fire in Phase A; it exists so nobody discovers the ceiling in
production.

Rewritten `load_models` becomes `build_pipeline(plan, models_dir)`: iterate `plan["graphs"]` in
order, construct `TensorflowPredictMusiCNN` or `TensorflowPredict2D` per `algorithm`, keep them in a
`{ref: instance}` dict. `plan["algorithms"]` are constructed the same way by name via `getattr(es,
name)(**params)`. Exit **2** on any construction failure — unchanged from `:82-86`.

Per file: decode once per distinct `plan["loads"]` entry into `{sample_rate: audio}`; run each graph
in plan order, caching outputs by `ref` (this is the embedding reuse at execution time); run each
algorithm; then walk `plan["emit"]` to project values out.

### 4.2 Is the manifest duplicated in Python? **No — and there is nothing to drift.**

Python never receives the manifest and has no concept of a descriptor, a class name, a native range,
or a unit. It receives graph filenames, output node names, algorithm names, tensor indices, and
output-port names — all resolved. There is exactly **one** copy of the manifest, in Ruby.

What *can* drift is the **plan schema**, and that is a much smaller and more tractable surface than
a duplicated manifest. Pin it three ways:

1. **`schema_version` integer in every plan.** Python rejects an unrecognised value with exit 2 and
   a message naming both versions. A gem/script mismatch fails loudly at preflight rather than
   producing subtly wrong output.
2. **The script ships inside the gem** (`SCRIPT_PATH`, `backends/essentia_python.rb:10`, resolved
   relative to `__dir__`). Ruby and Python are versioned and released as one artifact — they
   physically cannot be at different versions in a correctly installed gem. This is already true and
   is worth stating as a property being preserved.
3. **A golden plan fixture, asserted from both sides.** One committed JSON file, generated by
   `plan_for` in a Ruby spec and consumed by a pure-Python unit test (no Essentia import needed —
   plan parsing is separable from execution and must be kept so). Both specs run on a Mac. This is
   the only test that fails when someone changes the plan shape on one side only.

### 4.3 Typed NDJSON with provenance

```json
{"path":"/tmp/a.wav","schema_version":1,"values":{
  "mood_happy":{"kind":"scalar","value":0.8312,
                "provenance":{"algorithm":"TensorflowPredict2D","file":"mood_happy-msd-musicnn-1.pb"}},
  "valence_emomusic":{"kind":"scalar","value":4.191,
                "provenance":{"algorithm":"TensorflowPredict2D","file":"emomusic-msd-musicnn-2.pb"}},
  "bpm":{"kind":"scalar","value":118.24,
                "provenance":{"algorithm":"RhythmExtractor2013"}}},
 "runtime":{"essentia_version":"2.1-beta6-dev1389"}}
```

**Provenance is split deliberately.** Python emits only what it *observes* — which algorithm ran,
which file it opened, the Essentia version it imported. Everything *declared* — `model_version`,
`sha256`, `source_url`, `native_range`, `units`, `reduction` — is re-attached Ruby-side from the
registry row when constructing the `Value`. That is not an optimisation; it is the mechanism that
lets §4.2 be true. If Python emitted `model_version: "2"` it would need the manifest, and the
duplication question would be back.

Ruby-side cross-check on assembly: the `file` Python reports must equal the `filename` on the
registry's `Model` row for that descriptor. A mismatch is a `BackendError`. That is a cheap
tripwire on the one fact both sides independently touch.

### 4.4 Preserved properties, and what each costs

| Property | Where it lives today | Phase A status |
| --- | --- | --- |
| Subprocess isolation via `Open3.popen3(..., pgroup: true)` | `essentia_python.rb:31` | **Unchanged.** Not touched. |
| Per-file timeout, `STARTUP_GRACE + timeout_per_file` | `essentia_python.rb:9`, `:121-123` | **Formula unchanged; fit degrades.** See Risk 3. |
| Error taxonomy (3 members) | `essentia_python.rb:166-178`; emitted at `mood_probe_extract.py:96-136` | **Unchanged — no new members.** See below. |
| Non-finite guarding | `mood_probe_extract.py:109-125` | **Generalized + hardened.** See below. |
| NDJSON cardinality pinning (`lines.one?`) | `essentia_python.rb:151-152` | **Unchanged.** Still exactly one line per path. |
| Path echo-back check | `essentia_python.rb:155-157` | **Unchanged.** |
| Exit codes 0 / 1 / 2 | `mood_probe_extract.py:86`, `:139`, `:141`; consumed at `essentia_python.rb:131-142` | **Unchanged.** |
| Golden specs | gem `spec/integration/essentia_golden_spec.rb`; app `spec/integration/essentia_extract_golden_spec.rb` | **Changed — see §6.5.** |

**Error taxonomy — the decision to make explicitly.** With N descriptors per file, one failing DSP
pass could in principle be reported alongside N-1 successes. **Do not do this in Phase A.** Keep
whole-file atomicity: any failure in any requested descriptor yields exactly one `inference_error`
line for that file, as today (`mood_probe_extract.py:127-136`). Partial results are a new payload
state, a new consumer branch, and arguably a fourth taxonomy member — for a failure mode nobody has
observed. YAGNI. Recorded here so that if per-descriptor failure becomes painful in Tier 2/3 (a
malformed file that MusiCNN tolerates but `KeyExtractor` rejects is the plausible trigger), it is a
known deferred decision and not a surprise.

**Non-finite guarding — generalize, and harden the serialisation seam.** Today the guard is a flat
`math.isfinite` over a `{str: float}` dict (`:109-111`). It must walk typed values: scalars
directly, `Vector` element-wise, `Categorical` distributions element-wise. The guard surface grows
by ~200× the moment `:musicnn_embedding` is requested.

That matters because of what happens on a miss. Python's `json.dumps` emits bare `NaN` / `Infinity`,
which Ruby's `JSON.parse` **rejects** — so a non-finite that slips past the guard does not produce a
clean `MalformedOutputError`; it produces `BackendError: ... invalid NDJSON`
(`essentia_python.rb:162-163`), which is a *fatal* class that the app does not treat as a skippable
track (`mood_grounding_service.rb:94` rescues `MoodProbe::TrackError`; `BackendError` is a
`TrackError` per `errors.rb:9` — but `FatalError` subclasses are not, and the message is
misleading either way). **Add `json.dumps(payload, allow_nan=False)`.** A guard miss then raises
`ValueError` inside the existing per-file `try` and emits a proper `malformed_output` line. It is a
one-argument change that converts a confusing failure into the correct one, and it becomes more
valuable with every vector descriptor added. The existing `nan-audio` / `infinity-audio` fixtures
(`spec/support/fake_essentia/essentia/standard.py:52-55`, exercised at
`spec/integration/python_seam_spec.rb:41-53`) already give you the harness; add a vector-valued
sibling.

### 4.5 The emomusic rescale seam — exactly where it sits

**Remove from the gem, in one commit, both halves:**

- `mood_probe_extract.py:63-64` — `float((va_mean[0] - 1.0) / 8.0)` and the arousal twin. Emit
  `va_mean[0]` and `va_mean[1]` raw.
- `lib/mood_probe/features.rb:19` — `value.clamp(OUTPUT_RANGE)` for regression heads, and the
  `SANITY_RANGE`/`OUTPUT_RANGE` constants (`:6-7`) with it. `Features` as a class disappears; the
  registry's `range_kind` replaces its validation role (§1.2).

The gem then emits `:valence_emomusic` and `:arousal_emomusic` on their native `1.0..9.0`
(`range_kind: :nominal`), and asserts finiteness only.

**Add to vibe-doctor: `app/models/mood_vectors/essentia_mapper.rb`.**

Placement is per CLAUDE.md, and both halves of the rule point the same way. This is *domain* logic —
"how vibe-doctor's `MoodVector` columns are derived from Essentia descriptors" is a vibe-doctor rule,
not an I/O boundary — so it does not belong in `app/services` ("only for external integrations").
And it is a new SRP class belonging to `MoodVector`, so it goes under `app/models/mood_vectors/`,
alongside the existing `MoodVectors::VibePhraseBuilder` (`app/models/mood_vector.rb:16`).
`MoodProbe::Extractor` remains the external-integration boundary and is already injected directly
at `app/services/mood_grounding_service.rb:9-11` — no wrapper, per the prior review.

The mapper owns exactly two things:

```ruby
module MoodVectors
  class EssentiaMapper
    DESCRIPTORS = %i[
      valence_emomusic arousal_emomusic danceability mood_acoustic mood_relaxed mood_happy
    ].freeze

    EMOMUSIC_RANGE = (1.0..9.0)   # cross-checked against the gem registry at boot — see below

    def call(analysis)
      {
        valence: rescale_emomusic(analysis[:valence_emomusic].value),
        arousal: rescale_emomusic(analysis[:arousal_emomusic].value),
        danceability: analysis[:danceability].value,
        mood_acoustic: analysis[:mood_acoustic].value,
        mood_relaxed: analysis[:mood_relaxed].value,
        mood_happy: analysis[:mood_happy].value
      }
    end

    private

    def rescale_emomusic(value)
      ((value - EMOMUSIC_RANGE.begin) / (EMOMUSIC_RANGE.end - EMOMUSIC_RANGE.begin)).clamp(0.0, 1.0)
    end
  end
end
```

`(v - 1.0) / 8.0` is written as `(v - begin) / (end - begin)` so the rescale is visibly derived from
the declared range rather than being two more magic numbers — which is the entire point of decision
2's "declare the native range" clause.

**Two things that must not be missed:**

1. **The `.clamp(0.0, 1.0)` is not optional and is not cosmetic.** `MoodVector` validates every head
   into `0.0..1.0` (`app/models/mood_vector.rb:9`), and the plan doc records this as "Bug 2", closed
   in Phase 2 *by the gem's clamp*. Deleting `features.rb:19` **reopens Bug 2** unless the mapper
   clamps in the same deploy. An unbounded emomusic regression output of 0.97 or 9.2 maps to -0.004
   or 1.025, `mood_vector.update!` (`app/jobs/enrich_album_job.rb:26`) raises `RecordInvalid`, the
   album is marked failed — and per the plan doc's "Bug 1", recovery via `rake enrichment:backfill`
   is a dead end. **This is the single hardest sequencing constraint in the design (§6.1).**
2. **Assert the range agreement at boot or in a spec**, e.g.
   `MoodProbe::Registry.default.fetch(:valence_emomusic).native_range == EMOMUSIC_RANGE`. If the gem
   ever re-declares the range, vibe-doctor's rescale must fail loudly, not silently shift every
   album's valence. This is the one place the two repos share a number, so it is the one place worth
   a cross-repo assertion.

---

## 5. Versioning and migration (open question 2)

### 5.1 SemVer target: **0.2.0**

`MoodProbe::VERSION = "0.1.0"` (`lib/mood_probe/version.rb:2`). Under SemVer, 0.x minor bumps carry
breaking changes by definition, which is exactly what this is.

### 5.2 Deprecation shim: **none. Do not build one.**

Three independent reasons, any one sufficient:

- **0.x explicitly permits it.** No promise is being broken.
- **There is exactly one consumer**, pinned by revision (`Gemfile.lock:3`), in a repo the same person
  controls. A shim would ship to an audience of zero.
- **A `Features` compatibility shim would preserve the coupling the work exists to remove.** Keeping
  `Features` alive means keeping `HEADS` (`features.rb:3`) — vibe-doctor's six columns asserted as
  gem law — and keeping the emomusic rescale that §4.5 exists to delete. The shim is not neutral; it
  is the defect.

### 5.3 Compatibility surface worth keeping (and it is small and precise)

These are load-bearing at real call sites and should **not** change in 0.2.0. Pin them with an
explicit "public API" spec in the gem so the next breaking change is deliberate:

| Surface | Consumer call site |
| --- | --- |
| `MoodProbe::TrackError` (per-track, skippable) | `mood_grounding_service.rb:94`, `:108` |
| `MoodProbe::FatalError` (environment, abort the run) | `lib/tasks/enrichment.rake:5`, `:49`; `MoodGroundingService::SystematicTrackFailure < MoodProbe::FatalError`, `mood_grounding_service.rb:4` |
| `MoodProbe::UnreadableAudioError` | app golden spec `spec/integration/essentia_extract_golden_spec.rb:79` |
| `#verify!` | `enrich_album_job.rb:8`; `enrichment.rake:20`, `:44` |
| `Result` envelope: `#path` / `#ok?` / `#error`, positional 1:1 alignment | `result.rb:7-19`; relied on by `python_seam_spec.rb:36`, `:49` |
| Constructor kwargs `models_dir:`, `timeout_per_file:`, `python_executable:`, `backend:` | `mood_grounding_service.rb:9-11`; `enrich_album_job.rb:5-7`; `enrichment.rake:18-20`, `:31-33` |

Everything else — `Features`, `HEADS`, the flat hash from `#to_h`, `analyze`'s arity — may break.

Note the `TrackError`/`FatalError` split (`errors.rb:1-14`) is the prior review's contribution and is
the reason this migration is cheap on the app side: vibe-doctor rescues by *intent*, not by
enumeration, so adding descriptor-related error paths cannot silently change app behaviour.

### 5.4 Pinning: **move off the branch pin to a tag. The branch pin is the dangerous part.**

Current state: `Gemfile:34` is `gem "mood_probe", git: "https://github.com/Lhosb/mood_probe.git",
branch: "main"`; `Gemfile.lock:2-6` records `revision: 5360f8f...` with `branch: main`.

A branch pin is **safe for reproducibility and dangerous for lockstep**, and it is worth separating
those:

- *Safe:* the lockfile records an immutable revision, so `bundle install` is reproducible and CI's
  `bundler-cache: true` deployment-mode install fails loudly on an unreachable SHA.
- *Dangerous, three ways:*
  1. `bundle update mood_probe` — or a Dependabot bump, and this repo has active Dependabot PRs
     (recent commits `181d641`, `9ca16e0`, `72ae77d` are all bot bumps) — silently advances to
     branch head. With `main` carrying 0.2.0 and vibe-doctor's mapper not yet merged, that is a
     broken tree produced by a routine command.
  2. A force-push to the gem's `main` invalidates the recorded revision and breaks **every historical
     vibe-doctor checkout**, including the one you would reach for during a rollback.
  3. The coupling is invisible. Nothing at `Gemfile:34` says "this app requires gem ≥ 0.2.0".

**Recommendation:** tag the gem `v0.2.0` and pin vibe-doctor to the tag:

```ruby
gem "mood_probe", git: "https://github.com/Lhosb/mood_probe.git", tag: "v0.2.0"
```

A tag is immutable, makes the two-repo version coupling explicit and greppable, makes rollback a
one-line revert to `tag: "v0.1.0"`, and removes failure modes 1 and 2 outright. The cost is one
`git tag` per gem release — which is the correct amount of friction for a change that must land
in lockstep with a consumer.

**Release to RubyGems? No.** One consumer, a private-adjacent repo, weights-adjacent licensing
questions still open (per the prior plan's licensing section), and a permanent public namespace
claim — all for zero benefit over `git:` + `tag:`. Revisit only when a second consumer exists.
Note that a public RubyGems release also raises the question the prior review flagged: the gem
carries no weights, but its README and registry point at CC BY-NC-SA/ND artifacts, and publishing
makes that a wider audience's problem.

**Standing order, unchanged from the prior review and worth repeating because §6.1 depends on it:**
(1) commit, tag, and push the gem; (2) `bundle install` in the app; (3) commit the app's
`Gemfile.lock`. Never (3) before (1).

---

## 6. Sequencing (open question 7)

**I confirm the brief's proposed order** — registry + typed results + native values, migrate the
existing six, ship, then Tier 1 heads, then DSP tiers — with three changes, one of which is
load-bearing.

### 6.1 Phase A — **THE FIRST SHIPPABLE SLICE: "the same six numbers, through new pipes."**

**Gem (tag `v0.2.0`):** `Registry` with `Model` + `Descriptor` rows for exactly the current six
descriptors plus `:musicnn_embedding`; the `Value` hierarchy (`Scalar`/`Categorical`/`Vector`, plus
`Series` defined-not-registered); `Analysis`; `Provenance`; the Ruby planner; `Plan` + wire schema
v1; `mood_probe_extract.py` rewritten as a plan executor; **rescale and clamp deleted** (§4.5);
`Features`/`HEADS` deleted; `allow_nan=False`.

**vibe-doctor:** `MoodVectors::EssentiaMapper`; `MoodGroundingService` requests the six descriptors
explicitly and maps via the mapper (`mood_grounding_service.rb:93`, `:107` change from
`.analyze(path).to_h` to `.analyze(path, descriptors: EssentiaMapper::DESCRIPTORS)` piped through
the mapper); `Gemfile:34` → `tag: "v0.2.0"`.

**Must they land together? YES — this is the one phase where they must.** The gem's deleted
rescale and the mapper's added rescale are two halves of one behaviour; either alone changes every
album's valence and arousal. Two commits, one deploy, and the standing order in §5.4.

**Rollback:** revert vibe-doctor to `tag: "v0.1.0"` and revert the mapper commit. **Nothing else** —
and that is by design.

**The load-bearing change to the brief's plan: Phase A must contain no persistence change.**
`mood_vectors` schema untouched, no migration, no new columns, no JSONB blob. The brief lists
persistence under open question 4, and the temptation will be to bundle "while we're in here". Do
not. A schema-free Phase A means rollback is a two-line revert with **no data to reconcile**, and
that is the entire reason this is a safe first slice. Persistence lands in Phase C, when there is
actually something new to persist.

**The second change: register `:bpm` in Phase A, but do not consume it.** The brief defers all DSP
to a later tier. The problem is that a Phase A containing only MusiCNN heads exercises exactly one
planner code path — every descriptor is a `FromModel` on the same embedding, so `graphs` is never
empty, `loads` never has two entries, and `FromAlgorithm` is dead code. The planner's central claim
("BPM must not pay for MusiCNN") would ship **untested**. Adding `RhythmExtractor2013` costs roughly
15 lines of Python and one registry row, and it buys the §3.4 assertions — including the empty-models-dir
proof, which is the only test that cannot be faked. vibe-doctor requests nothing new; `:bpm` exists
solely as the planner's discriminating test surface. I recommend it explicitly, and flag it as the
one place I am proposing scope the brief did not.

**Phase A acceptance criteria:**
- The §6.5 algebraic parity gate passes **before** any golden file is rewritten.
- `plan_for(descriptors: [:bpm]).graphs.empty?`, and the empty-models-dir run succeeds in the image.
- `plan_for(descriptors: [:mood_happy, :mood_sad, ...]).graphs` contains **exactly one** MusiCNN entry.
- The registry loads and is fully introspectable with no Python and no models dir (§2.3).
- The golden plan fixture is asserted from Ruby and from Python (§4.2).
- `Registry.default.descriptors.none? { it.kind == :series }`.

### 6.2 Phase B — Tier 1 heads (`mood_sad`, `mood_aggressive`, `mood_party`, `mood_electronic`, `voice_instrumental`)

**Gem:** five `Model` rows + six `Descriptor` rows (`voice_instrumental` yields two, §1.3) + five
`.pb` checksums. **Zero Ruby code changes. Zero Python changes.** Tag `v0.3.0` (additive, but 0.x —
minor is fine either way).

**This phase is the falsifiable test of Phase A's architecture, and I want that stated as an
acceptance criterion: if Phase B requires touching `mood_probe_extract.py` or any `lib/` file other
than the registry, Phase A's design failed and should be revisited before Tier 2.** That is a cheap,
honest check and it is available for free.

**vibe-doctor:** nothing, unless it chooses to persist the new heads (open question 4 — not this
phase's problem).

**Must land together? No.** Gem-only. That decoupling *is* the payoff of the whole ticket.

**Rollback:** revert the gem tag bump in `Gemfile`. No app change to revert.

**Watch item:** three of the five have inverted class order (§0). The registry rows are the entire
defence. A spec asserting `classes` matches the upstream JSON verbatim — ideally a checked-in copy
of each `.json` next to each `.pb` checksum — is what makes this phase data-only *and* correct.

### 6.3 Phase C — Tier 2 DSP: `key` + `scale` via `KeyExtractor`

**Gem:** `FromAlgorithm` rows for `KeyExtractor`. This is the **first real `Categorical`** — Phase A
defines the type but never constructs one. VERIFIED outputs: `key` (string), `scale` (string),
`strength` (real); no distribution is available (Risk 8).

**vibe-doctor:** persistence and per-track→per-album aggregation (median + stability for tempo, a
representative key for `key`/`scale`, `match_confidence` weighting). This is open question 4 and
the first phase that needs a migration — hence the first phase with a real rollback story.

**Must land together? No**, provided vibe-doctor does not request them until its side is ready.
`descriptors:` being an explicit per-call list is what makes that true.

**Fixture warning:** the four existing fixtures (`chirp`, `clicks`, `sine_440`, `white_noise`) are
*adversarial* for tempo and key — only `clicks.wav` has any rhythm and none has a meaningful key.
Goldens generated from them would pin garbage and the gate would be decorative. Phase C must add
**one deterministic synthetic musical fixture** (e.g. a C-major arpeggio at a fixed 120 BPM) via the
existing `spec/fixtures/mood_probe/audio/generate.sh`. This is small and easy to forget.

### 6.4 Phases D and E

- **D — Tier 3 loudness.** `LoudnessEBUR128` → `integratedLoudness` (VERIFIED: real, LUFS),
  `loudnessRange` (VERIFIED: real, "dB, LU"); plus `DynamicComplexity`. Note `momentaryLoudness` and
  `shortTermLoudness` are VERIFIED `vector_real` — the natural first `Series`. **Do not build them.**
- **E — Tier 4 embeddings as stored output.** The first phase where `Vector` is persisted rather
  than merely returned, and the first with a real storage-size question. Discogs-EffNet
  (`genre_discogs400`) would be a second embedding model and the first genuine test of the planner's
  multi-embedding path.

### 6.5 Goldens — keeping a meaningful gate rather than regenerating into a tautology

**Current state, precisely.** There are two different gates and the dispatch's description matches
the app's, not the gem's:

- **App** — `spec/integration/essentia_extract_golden_spec.rb`: relative tolerance
  `max(1e-4 * |expected|, 1e-10)` (`:24-25`, computed `:53`, asserted `:68`), plus a key-set
  assertion on the **actual output** (`:41`) *and* on the golden file (`:42`), both against a
  hardcoded `MOOD_HEADS` constant (`:20`). It carries a calibration control in a comment (`:23`):
  a 0.900e-04 perturbation passed and 1.100e-04 failed. It ranks the worst head and prints a
  diagnostic including the CPU (`:26-28`, `:57-65`).
- **Gem** — `spec/integration/essentia_golden_spec.rb:34`: plain `eq(expected)`, **exact equality,
  no tolerance.**

The properties to preserve are the app spec's: **relative tolerance with an absolute floor**, and
**the key-set assertion on the output**. The latter is the anti-tautology device — rewriting the
golden file cannot satisfy `:41`, because `:41` compares the output against a constant the golden
file does not control.

**Rule 1 — never regenerate goldens and change behaviour in the same commit.** Phase A changes the
payload *shape* (typed) and the emomusic *value* (unrescaled). Both are unavoidable. What must not
change at the same time is *the numbers*.

**Rule 2 — Phase A's gate is an algebraic invariance gate against the OLD golden files, and it is
the most important test in the whole plan.** It is available for free and it cannot be satisfied by
regeneration:

- The four softmax heads are untouched by every Phase A change (no rescale, no clamp, same graph,
  same output node, same `mean(axis=0)`). Assert them **bit-identical** to the existing golden
  values — the gem's own `eq` standard, which is the right one here.
- Valence and arousal now arrive raw on `1.0..9.0`. Assert
  `(new_raw - 1.0) / 8.0` equals the **old golden value** within the existing
  `max(1e-4 * |expected|, 1e-10)` tolerance.

Both comparisons read the *unmodified* Phase-A-era golden files. Only once this passes do you write
the new-shape goldens. If someone regenerates first, the gate is gone and there is no way to
recover the evidence — so this ordering belongs in the phase's DoD as a hard step, not a suggestion.

**Rule 3 — replace the `MOOD_HEADS` constant with the requested descriptor list, and keep the
assertion on the output.** Assert `analysis.keys == requested_descriptors` **exactly** — same
members, and I would keep same order. This is the **load-bearing replacement for the deleted
`SchemaError`**: `Features#validate_keys!` (`features.rb:29-35`) currently raises on a missing *or
extra* head, and deleting `HEADS` deletes that guarantee. Moving it into `Analysis` (raise if the
backend returns a descriptor that was not requested, or omits one that was) keeps the property while
removing the coupling — the gem still refuses to return a payload that does not match the request,
it just no longer has an opinion about *which* descriptors those are. Say this explicitly in the
spec, or it will be lost as a side effect of deleting `Features`.

**Rule 4 — Phase B's gate is that the Phase A goldens re-run unchanged.** Adding five heads must not
move the existing six by a single bit. If any does, the embedding cache is broken — which is
precisely the failure mode Phase B introduces the risk of, and precisely the one a regenerated
golden would hide.

**Rule 5 — per-descriptor tolerance, chosen by units, each with its own calibration control.**
Relative tolerance is right for probabilities and BPM. It is **wrong for LUFS**, which is a dB
quantity that can be near zero or negative — a relative bound there is meaningless or infinite. Use
an absolute tolerance for `:lufs`/`:lu`. Keep this in the spec keyed by descriptor rather than
putting a `tolerance` field in the registry: tolerance is a property of the *test*, not of the
descriptor, and a registry field would invite production code to read it.

Every new tolerance must ship with its own calibration control in the manner of `:23` — a
perturbation just inside the bound that **passes** and one just outside that **fails**. A bound with
only a failing control proves nothing about whether the bound is achievable; a bound with only a
passing control proves nothing about whether it bites.

**Rule 6 — the gem's exact-`eq` gate and the app's tolerance gate should not silently converge.**
They test different things: the gem asserts its own determinism on fixed inputs in a fixed image;
the app asserts cross-environment reproducibility. Keeping both, with the gem staying exact, is
correct. Phase A should not "harmonise" them.

---

## 7. Risks, and the parts I am least sure about

**1. "Load audio once" is not literally achievable, and I cannot yet size the cost.** The script
loads at 16 kHz (`mood_probe_extract.py:47-49`), which MusiCNN requires (VERIFIED: upstream
`inference.sample_rate: 16000`). `RhythmExtractor2013`'s required input rate is **UNVERIFIED** — the
reference page does not state one, and 44.1 kHz is the convention. If it must run at 44.1 kHz the
planner decodes twice (§3.4 contrast case). For 30 s previews that is trivial; for a full album side
it is not, and vibe-doctor's future playlist work points that way. **Least sure:** whether running
`RhythmExtractor2013` at 16 kHz is acceptable — if it is, the plan collapses to a single decode and
settled decision 4 is literally true. This needs one measurement in the amd64 image and it should be
done in Phase A, while `:bpm` is being added, not in Phase C.

**2. Deleting the gem's clamp reopens Bug 2.** Covered at §4.5 and §6.1. It is the reason Phase A is
the one phase that must land in lockstep. I rate this the highest-probability way for Phase A to go
wrong, because it fails *later* than the change that caused it — at `mood_vector.update!`
(`enrich_album_job.rb:26`), on some future album with an extreme emomusic output, long after the
deploy looked clean.

**3. The timeout is now plan-dependent and the formula is not.**
`STARTUP_GRACE + timeout_per_file` (`essentia_python.rb:9`, `:121-123`) assumed a fixed workload:
one embedding plus five heads. A request for two DSP passes and twelve heads is a different order of
work under the same budget. Nothing breaks in Phase A (the plan is identical in cost to today), but
the abstraction is wrong from Phase C onward. I do not have a measurement to propose a better
formula and I would rather flag it than invent one. `Plan` should at minimum expose its step count
so a caller can size `timeout_per_file` deliberately.

**4. Two of the three planner proofs test a test double.** The fake Essentia double
(`spec/support/fake_essentia/essentia/standard.py`) is hand-written; "MusiCNN was never constructed"
asserted against it is a statement about the double. Only the empty-models-dir run in the real image
(§3.4 assertion 3) is unfakeable. **Least sure:** whether that image job will actually run. The
prior review found `ci.yml` had no rspec job and no image build; the plan doc records CI as
"authored (`96e546f`) ... **Never executed**". If the amd64 job is still not running on PRs, the
strongest gate in this design is a manual one-shot, and every phase's evidence rests on someone
remembering to run Docker. I would fix that before Phase A rather than after.

**5. The emomusic native range is UNVERIFIED at the authoritative source.** `models.html` states
`[1, 9]`; `emomusic-msd-musicnn-2.json` — the per-model metadata, which is where every other fact in
§1 came from — declares `classes: ["valence", "arousal"]` and **no range**. The 1–9 scale is a
property of the DEAM annotation protocol, which is where `(x - 1.0) / 8.0` came from. The registry
will declare `1.0..9.0 / :nominal`. **If that is wrong, vibe-doctor's rescale is wrong — and it is
equally wrong today** (`mood_probe_extract.py:63-64`), so this is not a regression, but Phase A is
the moment it becomes visible and cheap to check. Worth one empirical run: emit raw emomusic outputs
for the four fixtures and see where they actually fall.

**6. The `positive_index` → `classes` migration is the highest-consequence silent-correctness area,
and my confidence is uneven.** I fetched the `classes` arrays from upstream per-model JSON for nine
heads and I am confident in those. I have **not** obtained sha256 digests or `source_url`s for the
five Tier-1 models, and I did not re-verify the six existing digests. Phase B is data entry against
a source where three of five rows are counter-intuitive; it deserves a reviewer who checks each row
against the upstream JSON rather than against the neighbouring row.

**7. Two-repo lockstep, residual.** Tags remove the force-push and branch-drift failures (§5.4).
What remains: someone runs `bundle update`, or a Dependabot config that bumps git gems advances the
tag. Worth checking whether Dependabot is configured to touch git-sourced gems before Phase A; I did
not check `.github/dependabot.yml`.

**8. `Categorical` may be the weakest type in the hierarchy.** I designed it to carry a full
`distribution`, which is right for softmax heads. But `KeyExtractor` — the first real consumer —
returns only `key`, `scale`, `strength` (VERIFIED); there is no distribution to carry. So
`distribution` must be nullable, which means consumers cannot rely on it, which weakens the type to
"a label plus maybe some things". **Least sure:** whether `Categorical` should instead be two types
(a `Label` with an optional strength, and a `Distribution`), or whether the nullable field is fine.
I lean toward keeping one nullable-field type for now — the alternative is speculative structure for
one known case — but I would revisit it at Phase C when `KeyExtractor` actually lands, and I would
not be surprised to be wrong.

**9. What I did not verify.** Model digests and download URLs for Tier 1–4 (Security Reviewer's
scope). Whether any production album currently carries `mood_source: "essentia_itunes"` — no
database access. The Implementer's current-state inventory
(`docs/superpowers/specs/2026-08-10-essentia-gem-generalization-review/inventory.md`) had **not** landed when I wrote this; I
checked the directory and it contained only the three dispatch files. Everything I assert about
vibe-doctor's current behaviour I read directly and cited.

---

## 8. CHALLENGE — to the settled decisions

Neither of these changes the direction. Both change what gets built, so they need a decision rather
than a silent workaround.

### 8.1 Decision 2's premise is not quite true: the gem *is* applying an opinionated reduction, and it will still be after Phase A

Decision 2 says "the gem returns Essentia's **native** values" and "normalization: none in the gem."
But `TensorflowPredict2D` returns **per-frame** predictions, and the gem collapses them with
`predictions.mean(axis=0)` (`mood_probe_extract.py:59`, `:62`). That mean is a genuine analytical
choice — median, max, or a confidence-weighted mean over frames would all give different numbers,
and for a track with a quiet intro and a loud chorus they give *materially* different numbers. It is
normalization by another name, and it is currently invisible: nothing in the payload, the README, or
the registry records that it happened.

I am **not** proposing to expose the frame axis — that would make every scalar a `Series` and
explode the payload, which is exactly the over-engineering decision 3 rules out.

**I am proposing that the honest statement is "native units, with a gem-declared time reduction",
and that the reduction be declared in the registry** (`Model#reduction: :mean_over_frames`, §1.2)
and carried in `Provenance#reduction` (§2.2). Cost: one field on two structs. Benefit: the one
remaining opinion in the gem is visible to a consumer instead of buried in a Python one-liner, and
if a second consumer ever wants a median the extension point is already named. This is the same
argument decision 2 makes for native ranges, applied to the thing decision 2 overlooked.

### 8.2 Decision 4's "load audio once" should read "load audio once per required sample rate"

This is a factual correction rather than a disagreement — the *intent* (do not pay for work you did
not request) is right and the planner delivers it. But the literal wording will mislead whoever
implements `plan_for`, because MusiCNN requires 16 kHz (VERIFIED) and DSP algorithms conventionally
do not. The plan's `loads` array (§3.2) is keyed on sample rate for exactly this reason. See Risk 1
for the measurement that could make the original wording true after all.

---

## 9. Evidence

**Repo HEADs at time of reading:** vibe-doctor `0499d9cd38e7009eccbc6f75e50e93bd4800bc3e`;
mood_probe `5360f8fd8609eae39edb5dfab8a07f6439a0b137` (matches `Gemfile.lock:3`).

**Read in full — mood_probe:** `lib/mood_probe.rb`, `lib/mood_probe/model_registry.rb`,
`lib/mood_probe/features.rb`, `lib/mood_probe/result.rb`, `lib/mood_probe/extractor.rb`,
`lib/mood_probe/errors.rb`, `lib/mood_probe/model_store.rb`, `lib/mood_probe/version.rb`,
`lib/mood_probe/backends/essentia_python.rb`, `python/mood_probe_extract.py`, `Dockerfile.essentia`,
`spec/integration/essentia_golden_spec.rb`, `spec/integration/python_seam_spec.rb`,
`spec/model_registry_spec.rb`, `spec/support/fake_essentia/essentia/standard.py`,
`spec/fixtures/mood_probe/generate_goldens.rb`, `spec/fixtures/mood_probe/golden/sine_440.json`.
Partial: `spec/features_spec.rb` (1–50), `README.md` (1–70).

**Read in full — vibe-doctor:** `app/services/mood_grounding_service.rb`, `app/models/mood_vector.rb`,
`app/jobs/enrich_album_job.rb`, `lib/tasks/enrichment.rake`,
`spec/integration/essentia_extract_golden_spec.rb`, `spec/support/phase3_parity.rb`,
`spec/fixtures/mood_probe/generate_goldens.rb`, `app/services/mood_descriptor.rb` (1–60),
`CLAUDE.md`. Partial: `docs/superpowers/plans/2026-08-07-essentia-ruby-gem-extraction.md` (1–80),
`db/schema.rb` (`mood_vectors`, 93–108), `Gemfile` (28–40), `Gemfile.lock` (1–10, 484, 578).

**Also read:** the brief (`/Users/lukeolson/Downloads/mood_probe_gem_brainstorm_prompt.md`, full);
my session-local prior review `ESSENTIA-GEM/principal.md` (full; not included in this repository).

**Commands run (all read-only):** `git -C <repo> rev-parse HEAD` and `git log --oneline -5` on both
repos; `find`/`ls` over the gem tree, `app/`, `docs/superpowers/{plans,specs}/`,
the session-local ESSENTIA-GEM and ESSENTIA-GEM-V2 review directories; `grep` for `mood_probe` in `Gemfile.lock`, `essentia` in
`.gitignore`/`.dockerignore`, tolerance constants in `spec/`, and
`ENRICHMENT_VERSION|enrichment_version|CACHE_VERSION|backfill|re-?enrich|schema_version` across
`app/`, `config/`, `db/schema.rb`, `lib/tasks/`.

**Upstream Essentia documentation fetched** (the source for every VERIFIED marker):
`essentia.upf.edu/models.html`; per-model metadata JSON for `mood_relaxed`, `mood_happy`,
`mood_acoustic`, `danceability`, `mood_sad`, `mood_aggressive`, `mood_party`, `mood_electronic`,
`voice_instrumental`, `emomusic-msd-musicnn-2`, and `msd-musicnn-1`;
`reference/std_RhythmExtractor2013.html`; `reference/std_KeyExtractor.html`;
`reference/std_LoudnessEBUR128.html`; `tutorial_rhythm_beatdetection.html`.

**Corrections to facts stated in the dispatch** (both minor, both affect where to look):

1. The dispatch places the only production call site at `app/services/mood_grounding_service.rb:7`.
   It is at **`:9-11`** (the `feature_extractor:` constructor default), with the actual `analyze`
   calls at **`:93`** and **`:107`**. There is a second construction site at
   `app/jobs/enrich_album_job.rb:5-7` and a third and fourth in `lib/tasks/enrichment.rake:18-20`
   and `:31-33` — **four** construction sites, two analyze call sites. All four must move to the new
   `registry:`-aware constructor in Phase A.
2. The dispatch attributes the `max(1e-4 * |expected|, 1e-10)` tolerance and the output key-set
   assertion to "the current essentia golden spec". Those are properties of the **app's**
   `spec/integration/essentia_extract_golden_spec.rb:24-25`, `:41-42`, `:53`, `:68`. The **gem's**
   `spec/integration/essentia_golden_spec.rb:34` uses plain `eq` — exact equality, no tolerance.
   Both should be preserved, and they should be preserved *differently* (§6.5 Rule 6).

**Also worth recording, outside my scope but load-bearing for whoever owns open question 6:** the
brief states "versioned cache invalidation already exists in vibe-doctor — reuse it." I grepped
`app/`, `config/`, `db/schema.rb`, and `lib/tasks/` for `ENRICHMENT_VERSION`, `enrichment_version`,
`CACHE_VERSION`, and `schema_version` and found **no such mechanism for enrichment**. What exists is
`rake enrichment:reground_all` (`lib/tasks/enrichment.rake:14-26`), which calls `reset_enrichment!`
on **every** album unconditionally and re-runs the whole catalogue, and `query_understanding_caches`,
which is an unrelated table with an `expires_at` column (`db/schema.rb:110-123`). There is no
versioned, selective re-enrichment today. Whoever plans the backfill should not assume one is
available.
