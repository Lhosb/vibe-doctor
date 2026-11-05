# SONANCE-MAIN-AUDIT — GATE AUDIT (Test & TDD Enforcer)

# VERDICT: **PARTIALLY** — the gates prove the *mapping algebra* and the *dependency pin*, but four load-bearing behaviours have gates that cannot fail.

Gates that **cannot fail**, in severity order:

| # | Gate | What it cannot catch |
|---|------|----------------------|
| F1 | `spec/models/mood_vectors/essentia_mapper_spec.rb:53` (app) | A softmax head losing **half** its clamp — 298/298 stay green |
| F2 | `spec/descriptor_id_integrity_spec.rb:23-31` (gem) | A **wholly** stale descriptor array — i.e. exactly what a rename migration produces |
| F3 | `python/sonance_extract.py:506` `allow_nan=False` (gem) | Deleting the NaN seam guard — 194/194 stay green |
| F4 | `spec/integration/essentia_extract_golden_spec.rb` (app) | Running on a non-canonical / emulated machine — no guard at all |

Everything else I broke went red. Details, commands and pasted output below.

---

## 1. Suites — real counts, zero-failure status

Both suites are genuinely green. I did **not** hardcode expected counts; these are the observed totals.

```
GEM  /Users/lukeolson/projects/gems/mood_probe @ d514137 (main == origin/main)
$ bundle exec rspec --format progress
Run options: exclude {essentia: true}
194 examples, 0 failures          <- 0 pending, 0 skipped

APP  /Users/lukeolson/projects/vibe-doctor @ 1f8ad78 (tree byte-identical to origin/main b26cf31)
$ bin/rails assets:precompile     -> PRECOMPILE_EXIT=0
$ bundle exec rspec --format progress
298 examples, 0 failures          <- EXIT=0
```

The dispatch warned about ~7 Vibe Map JS system specs failing from missing compiled assets. I ran
`bin/rails assets:precompile` first and got **298 examples, 0 failures**. **No defect there** — the
warning is accurate and the remedy works.

I confirmed the app-tree-equals-main claim myself rather than taking it from CONTEXT.md:

```
$ git -C /Users/lukeolson/projects/vibe-doctor diff --stat HEAD origin/main
(empty)
```

### Silently excluded examples (F6, Medium)

```
GEM: $ ESSENTIA_SPECS=1 bundle exec rspec --dry-run            -> 208 examples
     $ ESSENTIA_SPECS=1 bundle exec rspec --tag essentia --dry-run -> 14 examples
APP: $ ESSENTIA_SPECS=1 bundle exec rspec --dry-run            -> 305 examples
     $ ESSENTIA_SPECS=1 bundle exec rspec --tag essentia --dry-run -> 7 examples
```

`spec_helper.rb:10` (gem) / `spec_helper.rb:17` (app): `config.filter_run_excluding essentia: true
unless ENV["ESSENTIA_SPECS"] == "1"`. A local green run is **194 of 208** and **298 of 305**.
RSpec prints `Run options: exclude {essentia: true}` but **no count**, so the developer is not told
that 14 / 7 examples did not run. Every example that actually executes Essentia is in the excluded
set. CI does cover them in Docker, so this is a local-confidence hazard, not a CI gap.

---

## 2. NON-VACUITY — does each gate run on a non-empty subject?

Checked **before** evaluating what each asserts, per the standing instruction. **All load-bearing
gates carry a real non-vacuity floor.** This is the one area where the earlier four-vacuous-gates
incident has been thoroughly and correctly addressed:

| Gate | Non-vacuity mechanism | Verified |
|------|----------------------|----------|
| gem `descriptor_id_integrity_spec.rb:11,42` | `raise "no descriptor source files discovered"` / `raise "no descriptor ids discovered"` | Guards exist, fire at load time |
| gem `baseline_v0_1_0_parity_spec.rb:5` | `raise "no baseline fixtures discovered" if …empty?` | 6 examples, 0 failures |
| gem CI `ci.yml` rspec job | `floor=$(find … \| wc -l)`, `test "$floor" -gt 0`, `test "$example_count" -ge "$floor"`, plus `failure/pending/error == 0` | Read; logic sound |
| gem CI `essentia_golden` job | same floor pattern computed inside the container | Read; logic sound |
| app `bin/essentia-ci` | `test "${#spec_files[@]}" -gt 0`; `floor=$((fixtures + 1))`; **asserts every golden fixture has a matching example** (`Golden fixtures without an Essentia example`); `test "$expected" -ge "$floor"`; re-greps `^${expected} examples, 0 failures$` | Executed — discovery found both spec files, 7 examples ≥ floor 5 |
| app `baseline_v0_1_0_integrity_spec.rb:23` | asserts the **file list** equals the digest-map keys before checking digests | Read; correct ordering |

`bin/essentia-ci` is the strongest non-vacuity gate in either repo — it is the only one that asserts
a *per-fixture* correspondence rather than a bare count. Nothing here is vacuous.

---

## 3. DOES IT BITE? — mutation battery

All mutations applied to **scratch copies outside both repos**:
`/tmp/sonance-audit-scratch/gem` and `/tmp/sonance-audit-scratch/app` (rsync, `.git` excluded).
Both real repos verified untouched at the end (§8).

Controls first: scratch gem `194 examples, 0 failures`; scratch app mood_vectors specs
`29 examples, 0 failures`. Every mutation below is reported against those passing controls.

### 3a. Gates that BITE (good)

| Mutation | Result | Gate that caught it |
|---|---|---|
| Drop emomusic normalization `(v-1.0)/8.0` → `v` | **298 → 12 failures** | mapper spec ×6, parity spec ×4, grounding service ×2 |
| Remove clamp entirely | **298 → 4 failures** | `essentia_mapper_spec.rb` only |
| Clamp → upper-only `[v,1.0].min` | **298 → 3 failures** | mapper spec |
| Clamp → lower-only `[v,0.0].max` | **298 → 3 failures** | mapper spec |
| Unclamp **each** of the 6 heads individually | **all 6 → RED** | mapper spec |
| Stale id in `EssentiaMapper::DESCRIPTORS` | **63 errors outside examples** | `config/initializers/sonance_registry.rb` — app cannot boot |
| `EMOMUSIC_RANGE` drift → `0.0..10.0` | **63 errors outside examples** | same initializer |
| Corrupt a golden value (chirp `mood_happy` ×2) | **6 → 2 failures** | gem `baseline_v0_1_0_parity_spec.rb` |
| Gem registry `native_range (1.0..9.0)` → `(0.0..10.0)` | **194 → 1 failure** | `spec/registry_spec.rb:110` |
| Neuter `EMULATED_CPU_PATTERN` | **194 → 2 failures** | `canonical_essentia_environment_spec.rb:71,122` |
| `CanonicalEssentiaEnvironment.verify!` → no-op | **194 → 7 failures** | `canonical_essentia_environment_spec.rb` |

**`config/initializers/sonance_registry.rb` is the strongest gate in the system.** It is not a test —
it is a boot-time assertion, so it fires in every environment including production, and it takes the
whole suite down (`0 examples, 0 failures, 63 errors occurred outside of examples`) rather than
failing one example. Both the stale-id and range-drift mutations were caught by it.

**Correction to a standing suspicion:** the clamp is **no longer** untested on half the heads.
I unclamped each of the six heads one at a time and every single one went red. The earlier
per-head gap has been fixed. The gap that remains is *directional*, not per-head — see F1.

### 3b. Mutations that stayed GREEN — the findings

---

## F1 — Softmax clamp: directional half-coverage (HIGH)

**File:** `spec/models/mood_vectors/essentia_mapper_spec.rb:53-67` (app)
**Protects:** `app/models/mood_vectors/essentia_mapper.rb:47-49`

The test is named *"clamps softmax heads to the MoodVector range"* and sets all four softmax heads at
once — which reads as full range coverage on all four. It is not. It parameterizes the **head** axis
but not the **direction** axis, giving each head exactly one bound:

```ruby
danceability_musicnn:  1.1,   # upper only  — no lower-bound coverage
mood_acoustic_musicnn: -0.1,  # lower only  — no upper-bound coverage
mood_relaxed_musicnn:  1.1,   # upper only  — no lower-bound coverage
mood_happy_musicnn:    -0.1   # lower only  — no upper-bound coverage
```

Demonstration — both mutations leave the **entire app suite green**:

```
=== danceability + mood_relaxed lose their LOWER bound only ===
24:        danceability: [ descriptors.fetch(:danceability_musicnn), 1.0 ].min,
26:        mood_relaxed: [ descriptors.fetch(:mood_relaxed_musicnn), 1.0 ].min,
298 examples, 0 failures

=== mood_acoustic + mood_happy lose their UPPER bound only ===
25:        mood_acoustic: [ descriptors.fetch(:mood_acoustic_musicnn), 0.0 ].max,
27:        mood_happy: [ descriptors.fetch(:mood_happy_musicnn), 0.0 ].max
298 examples, 0 failures
```

By contrast the two *emomusic* heads **are** covered in both directions (`9.4 → 1.0` and
`0.6 → 0.0`, lines 30-51). The asymmetry is invisible from the test names.

**Why nothing else covers it:** the clamp is inert on every golden. I mapped all 24 golden values
through the mapper's formula — every result lands strictly inside `[0,1]`:

```
chirp   mood_acoustic_musicnn  native= 0.002001  mapped= 0.002001
clicks  danceability_musicnn   native= 0.999997  mapped= 0.999997
white_noise mood_acoustic_musicnn native= 0.000000 mapped= 0.000000
… (24/24 in range, no line flagged CLAMP WOULD FIRE)
```

Confirmed by mutation: removing the clamp entirely produced failures **only** in
`essentia_mapper_spec.rb` — zero parity, golden, job or integration failures. Three unit examples
are the sole guard on this behaviour.

**Failure scenario:** a model swap or an Essentia upgrade emits a slightly negative
`danceability_musicnn` (softmax underflow, or a head that returns logits rather than probabilities).
The half-clamped mapper passes it through. The suite stays green.
**Mitigation that limits severity:** `app/models/mood_vector.rb:9` validates all six heads
`0.0..1.0` numerically, so the bad value is refused at save. The failure surfaces as a runtime
enrichment failure, not as stored bad data. Note there is **no DB check constraint** on the ranges —
`db/schema.rb` has a check constraint only on `mood_source` — so the model validation is the only
backstop.

**Fix:** give each softmax head both bounds (a `[head, direction]` product, not one direction each).

---

## F2 — The descriptor-id gate: its TRUE RULE (HIGH)

**File:** `spec/descriptor_id_integrity_spec.rb:23-38` (gem)

### Stated rule

I derived this from the code, then confirmed each clause by execution.

The gate collects an occurrence only in these two syntactic situations:

1. **`%i[…]` / `%w[…]` literal** — collected **only if** *(a)* the array already contains **at least
   one currently-valid descriptor id**, **or** *(b)* the ≤80 characters immediately before it end
   with the word `descriptor`/`descriptors`/`DESCRIPTORS` followed **only by non-word characters**
   (`/(?:\bdescriptors?\b|DESCRIPTORS)\W{0,80}\z/i`).
2. **`descriptors: [ … ]`** — a *literal* bracket array under that exact hash key, collected
   unconditionally.

**Therefore the gate can only ever detect a *partially* stale array.** A wholly stale array is
invisible, because clause (a) needs a surviving valid id to anchor on, and clause (b) fails for any
constant name where `descriptor` is followed by a word character — `DESCRIPTOR_IDS`,
`MOOD_DESCRIPTOR_SET`, `expected_descriptors` all break the `\b`.

**This is precisely the case a rename migration produces.** Renaming `valence → valence_emomusic`
across a list makes that list *wholly* stale. The gate passed the last migration only because the
arrays it happened to inspect were *mixed*.

### Demonstrated — the case it misses

```
=== MUTATION A: all-stale %i[] array named DESCRIPTOR_IDS ===
  DESCRIPTOR_IDS = %i[valence arousal mood_happy].freeze
1 example, 0 failures          <-- MISSED
```

```
=== MUTATION C: single stale id references (not an array) ===
  def self.primary_descriptor = :valence
  def self.lookup = Sonance::Registry.default.fetch(:mood_happy)
1 example, 0 failures          <-- MISSED
```

```
=== MUTATION D: plain bracket array of stale strings, no `descriptors:` key ===
  HEADS = [ "valence", "arousal", "mood_happy" ].freeze
1 example, 0 failures          <-- MISSED
```

### The passing control — proving the gate is not simply dead

```
=== MUTATION B: MIXED array (one valid id present) ===
  DESCRIPTOR_IDS = %i[valence_emomusic arousal mood_happy].freeze
       lib/sonance/zzz_probe_b.rb:3 mood_happy
1 example, 1 failure           <-- RED, as designed
```

Baseline control: `1 example, 0 failures` on the unmodified repo.

### What it also cannot see

- **`descriptors: CONSTANT`** — the regex requires a literal `[`, so the real production call
  `extractor.analyze(path, descriptors: DESCRIPTORS)` is never inspected.
- **The app repo entirely** — the gate globs `root` = gem root only. There is no app-side
  equivalent.

### What genuinely does protect this in the app

`config/initializers/sonance_registry.rb:3` (`DESCRIPTORS - registry.ids`) and
`spec/models/mood_vectors/essentia_registry_contract_spec.rb:8`. Both bite hard (§3a). Runtime is
also fail-closed — I confirmed the gem rejects an unregistered id loudly:

```
$ Sonance::Registry.default.fetch(:valence)
Sonance::ConfigurationError: unknown descriptor: valence; valid descriptors:
valence_emomusic, arousal_emomusic, danceability_musicnn, mood_acoustic_musicnn,
mood_relaxed_musicnn, mood_happy_musicnn, embedding_musicnn, bpm_rhythm2013,
beat_confidence_rhythm2013
```

(That output also *derives* the nine-id list from the code — it matches CONTEXT.md exactly. I did
not transcribe it.)

**Net:** the descriptor-id gate's green is close to meaningless for a rename migration. The real
protection is the initializer + contract spec, which cover `EssentiaMapper::DESCRIPTORS` only — see F5
for the copies they do not cover.

---

## F3 — The Ruby↔Python NaN seam guard is untested (HIGH)

**File:** `python/sonance_extract.py:506` — `print(json.dumps(payload, allow_nan=False), flush=True)`
**Consumer:** `lib/sonance/backends/essentia_python.rb:221` — `payload = JSON.parse(line)`

`allow_nan=False` is load-bearing: it is the only thing preventing Python from emitting a bare `NaN`
token that Ruby's parser rejects. Both halves demonstrated:

```
$ python3 -c "import json,math; print(json.dumps({'v': float('nan')}))"
python emits: {"v": NaN}

$ ruby -rjson -e 'JSON.parse(%q({"v": NaN}))'
Ruby JSON.parse rejects bare NaN: JSON::ParserError: unexpected token 'NaN}' at line 1 column 7

$ python3 -c "json.dumps({'v': float('nan')}, allow_nan=False)"
with allow_nan=False python raises: ValueError Out of range float values are not JSON compliant
```

Mutation — delete the guard, run the full gem suite:

```
=== GM1: remove allow_nan=False from the Python->Ruby seam ===
    print(json.dumps(payload), flush=True)
194 examples, 0 failures       <-- MISSED
```

Control: `194 examples, 0 failures` unmodified. I also grepped both repos for any NaN/Infinity
coverage — every hit was the substring `nan` inside `Sonance`/`Provenance`. **There is no test.**

**Failure scenario:** degenerate audio (digital silence, DC offset, a zero-length decode) makes an
Essentia head return NaN. With the guard, Python fails loudly with a JSON-compliance ValueError that
names the problem. Without it — and nothing would tell you it had been removed — Ruby raises
`JSON::ParserError: unexpected token 'NaN}'`, an opaque parse error attributed to the transport
rather than to the descriptor. The guard is correct today; it is simply unprotected against
regression.

**Fix:** one spec driving the fake-essentia backend to return `float('nan')` and asserting the loud
Python-side error crosses the seam intact.

---

## F4 — Environment sensitivity: the gem guards, the app does not (MEDIUM)

### The gem's guard is exemplary

`spec/support/canonical_essentia_environment.rb` **fails loudly and names the environment** in every
unmet-precondition case. It never silently skips and never silently passes. Verified on this arm64
host and by injection:

```
=== on THIS machine (arm64) ===
RAISED: Essentia goldens require native x86_64; this host is arm64, CPU is unknown CPU.
        Run the Dockerfile.essentia native x86_64 command documented in README.md.
        Set SONANCE_ALLOW_NON_CANONICAL=1 only for deliberate non-canonical investigation.

=== emulated amd64 (Docker on Apple Silicon) ===
RAISED: Essentia goldens require native x86_64; detected CPU emulation: VirtualApple @ 2.50GHz.
        AMD64 names an ISA, not an execution environment; emulated amd64 is non-canonical.

=== unknown-but-real x86 CPU — fail-closed? ===
RAISED: Essentia goldens require native x86_64; unrecognised CPU model: Intel(R) Core(TM) i9-9900K.
        This may be a legitimate native CPU not yet in the allowlist.
```

It is fail-closed on unknown CPUs, and it is applied at all three places that matter — the spec
(`essentia_golden_spec.rb:51,62`), the **generator** (`spec/fixtures/sonance/generate_goldens.rb:8`)
and the capture script (`script/capture_essentia_outputs.rb:6`). Guarding the generator, not just
the spec, is the right call. `spec/canonical_essentia_environment_spec.rb` covers 14 injected CPU
strings and goes **7 failures** red when the guard is neutered.

One escape hatch: `SONANCE_ALLOW_NON_CANONICAL=1` turns it into a **silent** pass — no warning
emitted. Given it must be set deliberately, that is acceptable, but a printed warning would cost
nothing.

### Correction on the "widening"

The dispatch flagged that the CPU pattern *"was recently widened after a runner change turned main
red."* I checked the diff rather than assuming it loosened anything:

```
$ git log --oneline -- spec/support/canonical_essentia_environment.rb
d514137 fix: accept current GitHub runner CPUs
- NATIVE_CPU_PATTERN = /(?:Intel\(R\) Xeon\(R\)|AMD EPYC)/
+ NATIVE_CPU_PATTERN = /(?:Intel\(R\)\s+Xeon\(R\)|AMD\s+EPYC)/i
```

It added **whitespace tolerance and case-insensitivity for the same two families**. It did **not**
admit any new CPU family. This is a safe fix, not a loosened gate, and the spec covers both the
mixed-case (`Amd Epyc 7763`) and upper-case (`INTEL(R) XEON(R) PLATINUM 8573C`) variants. No finding.

### The app has no equivalent guard — this is the finding

`spec/integration/essentia_extract_golden_spec.rb` has **no environment guard at all**.
`CPU_IDENTIFIER` (line 31) is interpolated into the failure diagnostic only (line 70) and is never
asserted on. The spec will compare floats on any machine that can run Essentia.

`spec/fixtures/sonance/generate_goldens.rb:16` guards only the ISA:

```ruby
abort("goldens require an amd64 runtime, got #{host_cpu}") unless %w[x86_64 amd64].include?(host_cpu)
```

```
=== app golden generator guard on THIS machine ===
app generator aborts: goldens require an amd64 runtime, got arm64
```

It names the environment when it aborts — good — but **emulated amd64 passes it**, where the gem's
guard rejects it by name. That asymmetry is how the goldens came to be generated under emulation
while CI extracts natively (the spec comment at lines 26-28 documents this as intentional, and the
1e-4 bound is sized to absorb it). It is a deliberate configuration, but it is held in place by a
comment rather than by a gate: nothing fails if someone regenerates the goldens on a *third* kind of
machine.

Root cause worth recording: the gem does not ship its `spec/` directory —
`sonance.gemspec:15-21` lists only `LICENSE.txt, NOTICE, README.md, exe/*, lib/**/*.rb, python/*.py` —
so `CanonicalEssentiaEnvironment` is gem-internal test tooling the app **cannot** reuse. The app had
to reimplement it, and reimplemented it weaker.

**Fix:** promote the canonical-environment check into `lib/` so both repos share one guard, or port
the emulation-rejection clause into the app's generator and add `verify!` to the app's golden spec.

---

## F5 — Duplicate descriptor lists in the app are not cross-checked (MEDIUM)

All **production** callers correctly reference the single constant
`MoodVectors::EssentiaMapper::DESCRIPTORS` — verified by deriving the caller list from code
(`enrich_album_job.rb:8`, `mood_grounding_service.rb:114,127`, `enrichment.rake:21,44`,
`sonance_registry.rb:3`). That part is clean.

But two **independent copies** of the same six ids exist and are gated by nothing:

- `spec/integration/essentia_extract_golden_spec.rb:20-23`
- `spec/fixtures/sonance/generate_goldens.rb:10-13`

Neither is checked against `EssentiaMapper::DESCRIPTORS` nor against `Sonance::Registry.default.ids`.
Mutation — drift the golden spec's copy (`valence_emomusic` → `valence`):

```
--- full local suite (what CI's `test` job runs):
298 examples, 0 failures       <-- MISSED
```

Only the Docker-only `essentia` CI job would surface it, and there it appears as an Essentia runtime
error rather than as "unregistered descriptor id". This is exactly the *"stale descriptor ids shipped
twice in sibling files because a gate was scoped to one filename"* failure mode, still live — the
app-side gate (`essentia_registry_contract_spec.rb`) is scoped to one constant, and F2 shows the
gem-side repo-wide gate would not see these either (wholly-stale array, and wrong repo).

**Fix:** one spec asserting both copies `== MoodVectors::EssentiaMapper::DESCRIPTORS`. Two lines.

---

## F6 — 7 app / 14 gem examples silently excluded locally (MEDIUM)

Covered in §1. Not a CI gap; a local-confidence gap. RSpec announces the *filter* but not the *count*.

---

## F7 — No test runs real Essentia output through the mapper (MEDIUM)

The app–gem seam is covered on both sides but **never as a composition**:

- `MoodGroundingService` — the only production path from audio to mood vector — is tested
  exclusively against `instance_double(Sonance::Extractor)`
  (`spec/services/mood_grounding_service_spec.rb:7`, with `allow(feature_extractor).to receive(:analyze)`
  at lines 42, 58, 68, 96…). No real extractor ever runs.
- `spec/integration/essentia_extract_golden_spec.rb` runs the **real** extractor but compares raw
  native values to goldens — it never calls `EssentiaMapper`.
- `spec/models/mood_vectors/essentia_parity_spec.rb:91-95` runs the **real mapper** but feeds it
  static golden JSON through `Sonance::AnalysisBuilder`.

So the handoff `Extractor#analyze(…).to_h.transform_values(&:value)` → `EssentiaMapper#call` is
verified only against a fixture, never against a live extraction. The shape contract (that `to_h`
keys are exactly the requested descriptor symbols) rests on a single assertion in the Docker-only
golden spec (`expect(actual.keys).to eq(DESCRIPTORS)`, line 46).

**Failure scenario:** a gem change to `Result#to_h` key type (symbol → string) or to the `.value`
accessor. The gem suite passes (its own specs use its own shape), the app suite passes (mocked
extractor + fixture-fed mapper), and the break appears only in the Docker essentia job — or in
production.

---

## F8 — Tolerance gates: bounds are correct, calibration is one-axis (LOW)

**Both** tolerance gates have a genuine inside-and-outside control pair. This meets the standard —
a failing case *with* its passing control — and I confirm it:

| Gate | Inside (must pass) | Outside (must fail) | Attribution asserted |
|---|---|---|---|
| app `essentia_parity_spec.rb:74,80` | `0.9e-4` | `1.1e-4` | `/chirp\.json golden mood_happy_musicnn/` |
| gem `baseline_v0_1_0_parity_spec.rb:31,37` | `0.9e-4` | `1.1e-4` | `/chirp\.json mood_happy drifted/` |

Both assert on the failure *message*, so the outside-control cannot be satisfied by an unrelated
failure. Both deliberately use literal decimals rather than deriving from `RELATIVE_TOLERANCE` — with
a comment saying so (`"deriving them from RELATIVE_TOLERANCE would let the control move with the
bound"`). That is exactly right.

The limitation: `with_perturbed_baseline` parameterizes the **magnitude** axis only. It hardcodes
`chirp.json` and `mood_happy`:

```ruby
path = baseline_root.join("chirp.json")
baseline["mood_happy"] += relative_delta * baseline.fetch("mood_happy").abs
```

So **1 of 24** comparisons has a calibration control. In particular, neither normalized head
(`valence`/`arousal`, which pass through `(v-1.0)/8.0`) is calibrated — the interaction between the
tolerance and the normalization is never probed at the boundary. The bound is uniform
(`[1e-4 * expected.abs, 1e-10].max`) so a single calibration is defensible; I rate this LOW. But the
comparison *coverage* is 24/24 while the *calibration* coverage is 1/24, and the test names do not
distinguish.

---

## F9 — The "24 comparisons" headline gates test fixtures, not code (LOW)

Both parity specs **re-implement** the normalization inline rather than calling the production mapper:

- app `essentia_parity_spec.rb:51` — `actual = descriptor.to_s.end_with?("_emomusic") ? (native_value - 1.0) / 8.0 : native_value`
- gem `baseline_v0_1_0_parity_spec.rb:72` — `actual = %w[valence arousal].include?(baseline_head) ? (raw - 1.0) / 8.0 : raw`

Demonstrated consequence — dropping the mapper's normalization leaves the headline example green:

```
rspec './spec/models/mood_vectors/essentia_parity_spec.rb[1:4]' # maps the chirp golden …      FAILED
rspec './spec/models/mood_vectors/essentia_parity_spec.rb[1:5]' # maps the clicks golden …     FAILED
rspec './spec/models/mood_vectors/essentia_parity_spec.rb[1:6]' # maps the sine_440 golden …   FAILED
rspec './spec/models/mood_vectors/essentia_parity_spec.rb[1:7]' # maps the white_noise golden … FAILED
# essentia_parity_spec.rb:68 "executes all 24 frozen-baseline comparisons"                     PASSED
```

The four per-fixture examples at line 88 **do** call the real mapper and **do** catch it, so the
behaviour is covered. But the gate that *sounds* like the flagship parity check is a
fixture-vs-fixture algebra check. The gem's version is stronger evidence of this: it never
references a single `Sonance` class — it compares two JSON files and can only ever detect fixture
corruption, never a port regression. Worth stating plainly so its green is not over-read.

---

## F10 — Nothing gates the pinned tag's reachability (LOW / informational)

I re-derived the structural fact rather than taking it from CONTEXT.md:

```
$ git rev-parse v0.3.0 v0.3.0^{commit}
cf8e613e9a9b3b3b576df4e20e61e63ec25dffe6      <- annotated tag object
66393972a8b57ee116afec0fbeb879a0c410dbca      <- peeled commit
$ git merge-base --is-ancestor v0.3.0^{commit} origin/main
NOT an ancestor of main
```

`spec/sonance_dependency_spec.rb` is a strong pin — it asserts `Sonance::VERSION == "0.3.0"`, the
lockfile remote and `tag: v0.3.0`, and `git rev-parse HEAD == 6639397` in the resolved gem path. It
runs locally (inside the 298) and would go red if the tag moved or the pin changed.

But no gate in either repo asserts that the pinned ref is **reachable from main**:

```
$ grep -rn "merge-base\|is-ancestor\|ancestor" <gem>/spec <app>/spec
(no matches)
```

The judgement on whether orphaned-history pinning is acceptable belongs to the deployability
reviewer. My finding is narrower and purely about coverage: **this condition is invisible to every
test in both repos.** If the gem repo ever prunes unreachable objects or the tag is deleted,
`bundle install` breaks with nothing having warned first.

---

## 4. WHAT IS NOT TESTED AT ALL

Ranked by seam, since absence of coverage on a seam is the finding:

1. **Ruby↔Python, NaN/Inf path** — F3. Guard exists, zero coverage.
2. **Extractor→Mapper composition (app–gem seam)** — F7. Each side tested, the join never is.
3. **Real-Essentia→mapper→persisted `MoodVector`** — no test anywhere carries a live extraction
   through to a saved row. `mood_vector.update!` (`enrich_album_job.rb:26`) is only ever reached with
   mocked extractor output.
4. **Clamp lower bound on `danceability`/`mood_relaxed`; upper bound on `mood_acoustic`/`mood_happy`** — F1.
5. **The two duplicate descriptor lists** — F5.
6. **Golden regeneration on a non-canonical machine (app side)** — F4.
7. **Tag-reachability of the pin** — F10.
8. **Calibration on 23 of 24 tolerance comparisons** — F8.

---

## 5. VERIFIED BY EXECUTION vs BELIEVED BY READING

**Verified by execution** (I ran it and read real output):
- Both suite counts and zero-failure status; the precompile remedy.
- App tree == `origin/main` (empty `git diff --stat`).
- Every row of the mutation table in §3a and §3b — each against a stated passing control.
- The descriptor-id gate's true rule: all four probe cases (A/B/C/D) plus baseline control.
- `allow_nan=False` removal leaving 194/194 green; Python NaN emission; Ruby NaN rejection.
- Canonical-environment guard behaviour on arm64, emulated amd64, unknown x86, and with the override.
- The CPU-pattern diff at `d514137`.
- Tag peel and non-ancestry.
- All 24 golden values landing inside `[0,1]` (clamp inert).
- `Sonance::Registry.default.fetch(:valence)` raising with the full valid-id list.
- `bin/essentia-ci` discovery + floor + dry-run stages.
- Both repos clean at finish.

**Believed by reading** (not executed — no Docker/Essentia on this host):
- That the gem's `essentia_offline_spec.rb` and `essentia_golden_spec.rb` (14 examples) pass in CI.
  I verified they exist, are discovered, and carry the environment guard; I could not run them.
- That the app's 7 essentia-tagged examples pass in the Docker job. Locally they fail with
  `Sonance::ConfigurationError: missing models directory` — an environment failure, **not** evidence
  of a defect, and I am not reporting it as one.
- The CI YAML floor arithmetic. I read it line by line and traced the logic; I did not run it under Actions.
- That `MoodVector`'s numericality validation is the only backstop for F1 — read from
  `mood_vector.rb:9` and `db/schema.rb`; not exercised with an out-of-range value.

---

## 6. EVIDENCE — commands run

```
git -C <gem> status --porcelain / rev-parse HEAD origin/main
git -C <app> status --porcelain / rev-parse HEAD origin/main / diff --stat HEAD origin/main
git -C <gem> rev-parse v0.3.0 v0.3.0^{commit}
git -C <gem> merge-base --is-ancestor v0.3.0^{commit} origin/main
git -C <gem> log --oneline -5 -- spec/support/canonical_essentia_environment.rb

cd <gem> && bundle exec rspec --format progress                              -> 194 examples, 0 failures
cd <gem> && ESSENTIA_SPECS=1 bundle exec rspec --dry-run                     -> 208 examples
cd <gem> && ESSENTIA_SPECS=1 bundle exec rspec --tag essentia --dry-run      -> 14 examples
cd <gem> && bundle exec rspec spec/baseline_v0_1_0_parity_spec.rb            -> 6 examples, 0 failures
cd <gem> && bundle exec rspec spec/descriptor_id_integrity_spec.rb           -> 1 example, 0 failures

cd <app> && bin/rails assets:precompile                                      -> exit 0
cd <app> && bundle exec rspec --format progress                              -> 298 examples, 0 failures
cd <app> && ESSENTIA_SPECS=1 bundle exec rspec --dry-run                     -> 305 examples
cd <app> && ESSENTIA_SPECS=1 bundle exec rspec --tag essentia --dry-run      -> 7 examples

# mutations — SCRATCH COPIES ONLY, outside both repos:
#   /tmp/sonance-audit-scratch/gem   (cp -R)
#   /tmp/sonance-audit-scratch/app   (rsync -a, .git/tmp/log/node_modules excluded)
# originals stashed at /tmp/sonance-audit-scratch/{mapper,py,registry,canon,chirp,golden_spec}.orig
# and restored after every mutation; each mutation reported against a stated passing control.
```

Full suite logs: `/tmp/maestri-reviews/SONANCE-MAIN-AUDIT/gem-suite.txt`, `app-suite.txt`,
`app-precompile.txt`.

## 7. FILES INSPECTED

**Gem:** `.github/workflows/ci.yml`, `.rspec`, `Rakefile`, `sonance.gemspec`, `spec/spec_helper.rb`,
`spec/descriptor_id_integrity_spec.rb`, `spec/baseline_v0_1_0_parity_spec.rb`,
`spec/canonical_essentia_environment_spec.rb`, `spec/support/canonical_essentia_environment.rb`,
`spec/registry_spec.rb`, `spec/integration/*`, `spec/fixtures/sonance/generate_goldens.rb`,
`lib/sonance/registry.rb`, `lib/sonance/backends/essentia_python.rb`, `python/sonance_extract.py`,
`script/capture_essentia_outputs.rb`.

**App:** `.github/workflows/ci.yml`, `bin/essentia-ci`, `spec/spec_helper.rb`,
`spec/sonance_dependency_spec.rb`, `spec/baseline_v0_1_0_integrity_spec.rb`,
`spec/models/mood_vectors/{essentia_mapper,essentia_parity,essentia_registry_contract}_spec.rb`,
`spec/integration/essentia_extract_golden_spec.rb`, `spec/services/mood_grounding_service_spec.rb`,
`spec/fixtures/sonance/generate_goldens.rb`, `app/models/mood_vectors/essentia_mapper.rb`,
`app/models/mood_vector.rb`, `app/services/mood_grounding_service.rb`, `app/jobs/enrich_album_job.rb`,
`lib/tasks/enrichment.rake`, `config/initializers/sonance_registry.rb`, `db/schema.rb`.

## 8. REPO STATE AT FINISH — READ-ONLY HONOURED

```
GEM /Users/lukeolson/projects/gems/mood_probe
  branch main, HEAD d514137a09facf8c64519e189aed57c3abaf5635
  git status --porcelain -> (empty)

APP /Users/lukeolson/projects/vibe-doctor
  branch docs/essentia-gem-v2-design, HEAD 1f8ad788844ba2cd4cd6cccf1491658cf06c5eab
  git status --porcelain -> ?? docs/superpowers/specs/2026-08-10-essentia-gem-generalization-review/phase-a/whole-branch/
```

That single untracked directory was present **before** this audit began (it appears in the session's
opening git status). I created, modified, staged, committed and deleted **nothing** in either
repository. All mutation work was done in `/tmp/sonance-audit-scratch/`, which remains on disk if
anyone wants to reproduce a result.

---

## 9. RECOMMENDED FIXES, ranked

1. **F1** — give each softmax head *both* clamp bounds. Product over `[head, direction]`, not one
   direction each. *(~6 lines)*
2. **F2** — the descriptor-id gate needs a rule that does not require a surviving valid id: e.g.
   collect every `%i[]`/`%w[]` whose *ids look like descriptor ids* and assert set membership, or
   simply assert equality against `Registry.default.ids` for the known constant names. Extend it to
   the app repo. Until then, do not treat its green as migration evidence.
3. **F3** — one spec forcing a NaN across the Python→Ruby seam.
4. **F5** — assert the two duplicate app descriptor lists equal `EssentiaMapper::DESCRIPTORS`. *(2 lines)*
5. **F4** — share one canonical-environment guard between the repos (move it into `lib/`), or port
   the emulation-rejection clause into the app.
6. **F7** — one Docker-job example carrying a live extraction through `EssentiaMapper` to a
   `MoodVector`.
7. **F8/F9** — extend the calibration control to at least one normalized head; consider renaming the
   fixture-vs-fixture examples so their scope is legible.
8. **F10** — decide whether tag reachability should be gated; if yes it is a one-line
   `git merge-base --is-ancestor` check in CI.

None of F1–F10 is evidence that the port is *wrong*. Every mutation that represented a real port
defect — dropped normalization, stale descriptor id, range drift, corrupted golden — was caught, most
of them loudly and at boot. The finding is narrower and specific to my remit: **four behaviours are
currently correct but unprotected, so nothing would tell you if they stopped being correct.**
