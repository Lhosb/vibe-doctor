# Phase A — Whole-Branch Integration Review — CODE QUALITY

VERDICT: APPROVE-WITH-FINDINGS

Diff range (gem, `git -C /Users/lukeolson/projects/gems/mood_probe`):
`55d85fb246e45581172d58066c24e41c8970ac9b..848f6894a6022b5a32ae2b6b0c6898ac84986fa0`
(26 commits, 65 files, +4716/-653). Tag `v0.2.0` confirmed to peel to `848f689`
(`git rev-parse v0.2.0^{commit}`). Working tree clean, `bundle exec rspec` 173/0,
`bundle exec rubocop` 46 files clean, `ruff check python spec/support` clean — all independently
reproduced, not taken on faith.

I read the Code Quality record for every slice (1 through 5b) before writing this. I do not repeat
anything already closed there. Everything below is either (a) new because it's a whole-branch seam no
per-slice diff could see, or (b) something a per-slice review's own scope legitimately excluded (the
gem's `exe/mood-probe` and `README.md`, which no single slice's diff touched as its primary subject).

---

## MUST-FIX

### 1. `exe/mood-probe analyze FILE` is broken as shipped — the CLI was never updated for the new `descriptors:` contract

**File/line:** `exe/mood-probe:42`. **Reproduced directly:**

```
$ ruby -Ilib exe/mood-probe --models-dir /tmp/mp_models_test analyze /nonexistent.wav
.../lib/mood_probe/extractor.rb:45:in 'MoodProbe::Extractor#analyze': missing keyword: :descriptors (ArgumentError)
    caller: exe/mood-probe:42
    |     puts JSON.pretty_generate(extractor.analyze(path).to_h)
```

`Extractor#analyze(path, descriptors:)` (`lib/mood_probe/extractor.rb:45`) made `descriptors:` a
required keyword — this is the entire point of Phase A (A1/A5/A6/G13: callers must name what they
want, the gem no longer assumes six fixed columns). But `exe/mood-probe`'s `analyze` subcommand
(line 42) still calls `extractor.analyze(path)` with zero arguments beyond the path, exactly as it did
at `main` (`55d85fb:exe/mood-probe:28`, pre-redesign: `def analyze(path)` — no descriptors, because
the old gem only ever produced the fixed six). The CLI subcommand was never touched by any of the five
slices' diffs to make it descriptor-aware, and the **README documents the broken command as the
primary example** (`README.md:22`: `mood-probe --models-dir /path/to/models analyze track.wav`) with
no `--descriptors` flag anywhere in `OptionParser` to even make it fixable from the command line as
shipped.

**Why no gate caught it:** every G-gate and every spec calls `Extractor#analyze`/`#analyze_all`
directly in Ruby with an explicit `descriptors:` argument (`spec/integration/essentia_golden_spec.rb`,
`extractor_spec.rb`, etc.) — nothing in the suite invokes `exe/mood-probe analyze` as a subprocess.
`spec/license_notice_spec.rb` and `spec/model_store_spec.rb` exercise the `models verify`/`models
fetch` subcommands (which don't take descriptors and were correctly updated), but no spec exists for
`analyze` at all.

**Failure scenario:** any consumer following the README's own usage example (`mood-probe
--models-dir ... analyze track.wav`) gets an `ArgumentError` stack trace instead of a JSON result,
on the first real invocation of the gem's primary documented CLI verb.

**Concrete fix:** add a `--descriptors a,b,c` (or similar) `OptionParser` flag, split/symbolize it, and
pass `descriptors: parsed` into the `analyze` branch; add a spec that shells out to `exe/mood-probe
analyze` (mirroring the existing `license_notice_spec.rb`'s subprocess pattern) so this class of
CLI/library drift cannot recur silently. Until this lands, the CLI is not usable for its one
documented purpose.

---

### 2. README's opening sentence still describes the OLD, opinionated gem, not the one this branch built

**File/line:** `README.md:3-4`. **Verified verbatim, unchanged since before this branch:**

> `mood_probe` extracts six normalized mood features from audio using an operator-provided Essentia
> Python installation and six separately licensed TensorFlow model files.

This is the exact framing the design doc's own J.4 preamble explicitly moves away from: "the
`mood_probe` gem stops being a mirror of vibe-doctor's six mood columns and becomes a descriptor
registry with typed results and an extraction planner." The redesigned gem's registry now holds **nine
descriptors** (`valence_emomusic`, `arousal_emomusic`, `danceability`, `mood_acoustic`, `mood_relaxed`,
`mood_happy`, `musicnn_embedding`, `bpm`, `beat_confidence` — confirmed via
`Registry.default.ids`), can be asked for **any subset** (G4/G7/G13 exist specifically to prove
partial requests work and are independently preflighted), and G4 proves a `[:bpm]`-only request needs
**zero** model files. "Extracts six normalized mood features... using... six separately licensed
TensorFlow model files" is not just outdated color — it restates vibe-doctor's opinion (fixed six
mood outputs) as the gem's own self-description, in the first sentence a new consumer reads, directly
contradicting the acceptance criterion this whole review is measuring against ("a less opinionated
Ruby wrapper of Essentia"). The rest of the README (the code sample at line 9-14, the security notes)
is already accurate and descriptor-based — only the framing sentence at the top was never revisited.

**Concrete fix:** rewrite the opening sentence to describe the registry/planner shape (e.g., "`mood_probe`
extracts named audio descriptors — scalars, categorical labels, and a raw embedding — from a
declarative registry of Essentia models and algorithms, using an operator-provided Essentia Python
installation."). Small, mechanical, but this is the one sentence most likely to set a new contributor's
mental model, and right now it sets the wrong one.

---

## SHOULD-FIX

### 3. `extractor.rb:58`'s concrete-class check means the "stops the batch" contract (G13) is verified only against a code path production never executes

**File/line:** `lib/mood_probe/extractor.rb:58` — `if backend.is_a?(Backends::EssentiaPython)`.

**What it costs, verified directly, not assumed:**

- `Backends::EssentiaPython` is the **only** concrete backend implementation anywhere in this codebase
  (`grep -rn "def analyze\b" lib/` returns exactly two hits: the real backend and `Extractor` itself).
  There is no second production backend and no `Backend` interface/module either class includes.
  The `else` branch (`normalized_paths.map { backend.analyze(path, plan:) }`, serial, one call per
  file) is therefore **dead in production** — it is only ever reached by RSpec test doubles.
- I traced where it *is* reached: `spec/extractor_v2_spec.rb`'s `backend` double stubs `analyze:` only
  (no `analyze_all`), so `backend.is_a?(Backends::EssentiaPython)` is `false` for it, routing every
  example in that file through the never-in-production serial branch. That includes the file's three
  examples asserting `MoodProbe::SchemaError` "raises and stops the batch for..." (unrequested id,
  missing id, wrong value type) — the direct test coverage for **G13**, a named J.4 evidence gate.
- I then checked whether the **real batch path** is tested for the same contract and it is not:
  `spec/integration/python_plan_executor_spec.rb` tests `MalformedOutputError` isolation through the
  real subprocess ("isolates a non-finite descriptor within a real subprocess batch" — correctly
  *continues* past a bad track, per the Slice 5 skipped-track ruling), but nothing exercises a
  `SchemaError` (unrequested/missing/wrong-type) through the real `EssentiaPython#analyze_all` →
  `parse_results` → `Extractor#result_for_outcome` path.
- The two paths are not merely stylistically different, they already have **different real semantics**
  for "stops the batch": in the serial/double path, `backend.analyze` for track 2 is provably never
  called once track 1 raises (`expect(backend).not_to have_received(:analyze).with(Pathname("two.wav"), ...)`).
  In the real batch path, the single subprocess invocation has **already produced output for every
  file** (that's the whole point of batching — one shared embedding, per G6) before Ruby ever raises;
  "stopping the batch" there can only mean "the caller doesn't get a `Result` for track 2," not "track
  2 was never analyzed." Nothing currently proves the real path actually delivers even that narrower
  guarantee — `result_for_values` only rescues `MalformedOutputError`, so a `SchemaError` from
  `analysis_builder.call` would propagate out of the `.map` in `analyze_all` as expected, but this has
  never been exercised end-to-end through the real backend to confirm it.

**The drift risk this creates:** if a future change made `result_for_values` also rescue `SchemaError`
(to "isolate" it the way `MalformedOutputError` is isolated — a plausible, easy-to-make edit given the
two rescue clauses sit two lines apart), G13's "stops the batch" spec would keep passing unchanged,
because it never touches the real backend. Production behavior would have silently diverged from a
named J.4 gate with a green suite.

**Clean factoring:** replace the `is_a?` branch with an unconditional `backend.analyze_all(...)` call,
and give the `extractor_v2_spec.rb` double an `analyze_all` implementation (a one-line
`->(paths, plan:) { paths.map { |p| analyze(p, plan:) } }` stub, or a small shared test module) so the
same method name is exercised in both unit and integration specs. This removes the concrete-class
coupling entirely and makes "which branch runs" no longer a function of `backend.class`. Not a
blocker — the `result_for_outcome`/`result_for_values` mapping itself genuinely is shared and correct
between the two call sites, so there is no live bug today, but the untested divergence risk is real and
cheap to close.

### 4. `registry.rb` mixes three genuinely different concerns in one 338-line file, and it shows in the rubocop-disable markers

**File:** `lib/mood_probe/registry.rb`. Measured directly: of 338 lines, the `Model`/`FromModel`/
`FromAlgorithm`/`Descriptor` type+validation definitions are ~83 lines (1-83); the **literal upstream
model/descriptor manifest** (`default_models`, `model`, `default_descriptors`,
`emomusic_descriptor`/`probability_descriptor`/`rhythm_descriptor`) is ~210 lines (85-297, over 60% of
the file); the `Registry` class's actual query API (`ids`/`fetch`/`model`/`deep_freeze`) is ~30 lines.
The file carries three `rubocop:disable` markers (`Metrics/ClassLength`, `Metrics/MethodLength`,
`Naming/VariableNumber`) — I checked, and all three exist **solely because of the literal manifest
block**; the `Registry` class body itself (lines 299-338) would need none of them if isolated.

Slice 2's Code Quality review (which I am not re-litigating) correctly judged the manifest-as-literal
choice itself as right ("deliberately literal so upstream model facts remain reviewable together") —
I agree, and I'm not questioning that decision. What I'm flagging is a level up: the manifest doesn't
need to share a *file* with the `Model`/`Descriptor` type definitions and the `Registry` class's lookup
logic to remain reviewable as one diff. Moving `default_models`/`default_descriptors`/the three
descriptor-builder helpers into a sibling file (e.g. `lib/mood_probe/registry/defaults.rb`, required by
`registry.rb`, or a data-only module `MoodProbe::Registry::Defaults`) would let a future reviewer of
"did someone change a validation rule" vs. "did someone change a model fact" look at two different,
appropriately-sized diffs instead of one 338-line one, and would let the three rubocop-disables be
scoped to (and travel with) the data file rather than sitting above the class that doesn't need them.
This is not a correctness issue and suites are green either way — it's a readability/navigability
recommendation for whoever edits this next (plausibly Phase B's B1, which adds five more `Model` rows
to exactly this manifest).

### 5. Python `main()` has grown into the same shape `validate_plan` was before slice 3 fixed it — 98 lines, three levels of nested nested try/except, never decomposed

**File/line:** `python/mood_probe_extract.py:494-591`. Measured via AST: `main` is now the **largest
function in the file** at 98 lines (validate_plan was 173 before slice 3 split it into
`validate_plan_keys`/`validate_loads`/`validate_graphs`/`validate_algorithms`/`validate_emits`, now 21
lines; `validate_emits` at 54 lines is the current largest non-`main` function). `main`'s per-track loop
(`for raw_path in args.audio_paths:`, lines 532-575, ~44 lines) nests three `try/except` levels deep —
outer crash guard, per-track `unreadable_audio` guard, per-track `inference_error` guard, per-track
serialization guard — each wrapping the next and each duplicating the same `emit({"path": ..., "error":
{"type": ..., "message": ...}})` shape by hand. This is legible today (each block is short and each
error type is named), but it is exactly the "one function doing five things" shape this codebase
already recognized and fixed once in `validate_plan`, and it's the one place in the file that a Phase C
contributor adding a sixth error type (or a new per-track post-processing step) is most likely to make
the mistake slice 3's fix pattern exists to prevent.

**Concrete fix:** extract the loop body into a named `process_track(raw_path, plan, loaded_models) ->
dict` function returning the payload to `emit`, following exactly the section-based decomposition
`validate_plan` already got. Not a blocker — the function is within Python readability norms for its
domain and every branch is spec-covered — but it's the one piece of this 562-line growth that didn't
get the same "decompose by section" treatment the rest of the file did, and it would be measurably
cheaper to fix now than after Phase C adds a fourth per-track error path.

---

## NIT

### 6. Model/Descriptor construction errors use `ArgumentError`; Value/Result construction errors use the gem's own `SchemaError`/`MalformedOutputError` — a defensible but unexplained split

`registry.rb`'s `Model#validate_filename!`/`validate_source_url!`/`validate_integrity_metadata!` and
`Descriptor#initialize`'s hard-range check all raise plain Ruby `ArgumentError`. `value.rb`'s
`Value#validate_kind!`/`validate_numeric!`/`validate_sanity_range!` (and `AnalysisBuilder`'s
`validate_requested_set!`) raise the gem's own `SchemaError`/`MalformedOutputError`. Both are "this
constructor received bad data" checks; a contributor could reasonably wonder why one category uses a
stdlib error and the other a domain-specific hierarchy. The distinction is plausibly intentional and
defensible (Model/Descriptor errors fire only against the hardcoded manifest at `Registry.default` load
time — a static-data-authoring mistake, closer to Ruby's own keyword-arg type checking — while
Value/Result errors fire against runtime pipeline output a caller may want to rescue by class), but
nothing in the code says so. A one-line comment at either `Model`'s or `Value`'s validation section
naming the distinction would remove the ambiguity for the next person who adds a validated field to
either. Not requesting a change of the error classes themselves.

---

## Confirmed clean — items I checked myself, not repeated from other reviewers

- **No leftovers from `features.rb`/`model_registry.rb`.** `grep -rn "features\.rb|Features\b|model_registry|ModelRegistry\b"` across the whole gem tree returns exactly one hit: `spec/registry_spec.rb:72`'s
  intentional `expect(defined?(MoodProbe::ModelRegistry)).to be_nil` removal-assertion. No stale
  requires, no orphaned fixtures, no README/NOTICE/`exe/mood-probe` reference to the deleted classes.
- **`spec/support/phase3_parity.rb` (app repo) is deleted and gone from the tracked tree** — confirmed
  via `git ls-tree -r HEAD --name-only | grep phase3` (empty) and `git log --diff-filter=D` showing the
  deleting commit (`83765e4`, Slice 5a, already reviewed and closed there). The two `.worktrees/` hits I
  found are stale checkouts of unrelated older branches, not part of this branch or this review.
- **Fixtures are all live**, none orphaned: `clicks_44100.wav` and `generate.sh`'s corresponding block
  are both consumed by `spec/integration/essentia_offline_spec.rb` (byte-identity + native-BPM
  assertions), confirmed via grep.
- **Result-mapping between the two `analyze_all` branches (Finding 3) is genuinely shared, not
  duplicated** — both call the same `result_for_outcome`/`result_for_values` pair; the only difference
  is invocation shape, not mapping logic.
- **Validation is not duplicated across `Model`, `Descriptor`, and `Value`** — each validates entirely
  different invariants (filename/URL/hash shape vs. range-kind consistency vs. numeric/finite/sanity
  range); `Value`'s shared numeric/finite checks are correctly centralized on the `Value` base class,
  as slice 2's review already found and I re-confirmed by inspection.
- **Keyword-argument shorthand (`foo:` not `foo: foo`) is used consistently** across every changed file
  — checked via grep for the `word: word` pattern, zero hits.
- **`Set` vs. `Array#uniq`** usage is not an inconsistency: `extractor.rb`'s `Set` is used where
  membership/`subset?`/`merge` set-algebra is actually needed; `plan.rb`'s `Array#uniq` is used where
  insertion order must be preserved for stable graph/algorithm refs. Different needs, correctly
  different tools.
- **RuboCop 46 files, zero offenses; ruff on `python spec/support`, all checks passed; RSpec 173/0** —
  reproduced myself at `848f689`, not taken from the manager's pre-verification.

---

## Evidence

```
$ git -C /Users/lukeolson/projects/gems/mood_probe log --oneline 55d85fb..848f689 | wc -l   # 26
$ git -C /Users/lukeolson/projects/gems/mood_probe diff 55d85fb..848f689 --stat | tail -1   # 65 files, +4716/-653
$ git -C /Users/lukeolson/projects/gems/mood_probe rev-parse v0.2.0^{commit}                # 848f6894a6022b5a32ae2b6b0c6898ac84986fa0
$ git -C /Users/lukeolson/projects/gems/mood_probe status --porcelain                       # (clean)
$ bundle exec rspec        # 173 examples, 0 failures
$ bundle exec rubocop      # 46 files inspected, no offenses detected
$ ruff check python spec/support   # All checks passed!

$ ruby -Ilib exe/mood-probe --models-dir /tmp/mp_models_test analyze /nonexistent.wav
# ArgumentError: missing keyword: :descriptors, raised from extractor.rb:45, called from exe/mood-probe:42

$ grep -n "analyze" README.md   # line 22 documents the broken command; no --descriptors flag exists
$ git -C . show 55d85fb:exe/mood-probe | grep -n "def analyze"   # pre-branch: def analyze(path) — no descriptors, matches old CLI

$ grep -rn "def analyze\b" lib/mood_probe/   # exactly 2 concrete implementations: essentia_python.rb, extractor.rb
$ sed -n '95,131p' spec/extractor_v2_spec.rb   # double stubs analyze: only; "stops the batch" specs run through it
$ grep -n "SchemaError" spec/integration/python_plan_executor_spec.rb spec/backends/essentia_python_spec.rb
  # (no output — SchemaError/"stops the batch" never exercised through the real batch backend)

$ python3 -c '<ast function-size measurement>'   # main=98 (largest), validate_emits=54 (largest non-main)
$ awk 'NR==85,NR==297' lib/mood_probe/registry.rb | wc -l   # ~210 lines of literal manifest data
$ grep -n "rubocop:disable" lib/mood_probe/registry.rb      # 1 marker, spans exactly the manifest block

$ grep -rn "features\.rb\|Features\\b\|model_registry\|ModelRegistry\\b" .   # only the intentional removal-assertion
$ git -C /Users/lukeolson/projects/vibe-doctor ls-tree -r HEAD --name-only | grep phase3   # (empty)
$ grep -rn "clicks_44100" --include="*.rb" .   # consumed by essentia_offline_spec.rb, not orphaned
```

Files inspected in full: `lib/mood_probe/extractor.rb`, `lib/mood_probe/registry.rb`,
`lib/mood_probe/value.rb`, `lib/mood_probe/plan.rb`, `lib/mood_probe/backends/essentia_python.rb`,
`exe/mood-probe`, `README.md`, `NOTICE`, `python/mood_probe_extract.py` (full, plus AST measurement),
`spec/extractor_v2_spec.rb`, `spec/integration/python_plan_executor_spec.rb`,
`spec/backends/essentia_python_spec.rb`, `spec/registry_spec.rb`, plus every Code Quality report from
slices 1 through 5b.
