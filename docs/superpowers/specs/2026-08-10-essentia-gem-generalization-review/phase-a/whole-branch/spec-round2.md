# ESSENTIA-GEM-V2 — 0.2.1 remediation re-review (SPEC)

**VERDICT: APPROVE-WITH-FINDINGS**

**Range:** `848f6894a6022b5a32ae2b6b0c6898ac84986fa0..036c797f87e8a490dbcc676da0e7bfce8e0fb298`
(21 files, +327/−31, six commits) on `feat/essentia-gem-v2-phase-a`.
**Baseline challenged, not assumed — it holds:** tree clean, `rspec` **184 / 0**, `rubocop` **48 files,
0 offenses**, `VERSION = "0.2.1"`, `git tag` → `v0.1.0` and `v0.2.0` only, and `v0.2.0^{}` still peels
to `848f6894…`. No tag moved, none created.

**Every round-1 finding of mine is CLOSED** except the rename, which is OPEN-BY-RULING, and two NITs I
did not ask to be fixed. **I found no regression in code** — I probed the two changes most likely to
cause one and both check out, with evidence below.

**The two new findings are both in the README sections that were newly added**, which is where the
dispatch predicted a repeat defect would live. Neither is a misstatement of a fact; both are
*under-specifications that would send a consumer to the wrong place*.

---

## Rulings on my round-1 findings

| # | Finding | Ruling | Proof |
| --- | --- | --- | --- |
| MUST-FIX 1 | README advertised v0.1.0's product | **CLOSED** | `README.md:3-8`, `:12-18` |
| SHOULD-FIX 1 | unknown descriptor id escaped `MoodProbe::Error` | **CLOSED** | `registry.rb` `fetch` block; verified by execution |
| SHOULD-FIX 2 | public type system undocumented | **CLOSED** | `value.rb`, `errors.rb` YARD; all three of my questions answered |
| SHOULD-FIX 3 | `Model.new` could not register a self-hosted model | **CLOSED**, and better than asked | `model_store.rb` `validate_download_uri!`; verified both directions |
| SHOULD-FIX 4 | the gem name is a misnomer | **OPEN-BY-RULING** — deferred to a user decision, not a failure |
| SHOULD-FIX 5 | gem `golden/` had no provenance record | **CLOSED** | `spec/fixtures/mood_probe/golden/PROVENANCE.md:3-4` |
| NIT 1 | `Registry.default` is one app's shopping list | **CLOSED** | `README.md:20-21` |
| NIT 2 | `mean_over_frames` is the only reduction | still true, **not addressed** — restated below |
| NIT 3 | descriptor-id naming inconsistent | still true, **not addressed** — restated below |

### MUST-FIX 1 — CLOSED. The README now describes the artifact that ships.

Read as the stranger I described in round 1, `README.md:3-8` delivers all four things I asked for:

> "`mood_probe` extracts **a registry of Essentia descriptors** from audio… Values are emitted in each
> descriptor's **native range, declared on its registry row; normalization is the consumer's
> responsibility**. **Demand-driven planning** verifies only the model files required by the requested
> descriptors, and **`[:bpm]` requires no model files**."

Native ranges ✅ · consumer-owned normalization ✅ · demand-driven planning ✅ · model-free `bpm` ✅.
Both false claims are gone: no "normalized", no "six mood features", no implication that six `.pb`
files are prerequisites.

**On "nine descriptors": the README does not state a count, and I rule that better than stating one.**
It ships `mood-probe descriptors` (`README.md:28`, `exe/mood-probe:47-48`) which prints the live list —
verified, it emits all nine. A hardcoded count is exactly what went stale last time; a command cannot.

**The example is free of vibe-doctor's six**: `%i[bpm musicnn_embedding]` (`:14`). That is a good choice
rather than a merely compliant one — it is the one pair that demonstrates both capabilities the old
README concealed (a model-free descriptor and a vector-valued one).

One residual "six" at `:70` — "compares all six descriptor values at the calibrated bound" — is
**correct**: the gem's golden fixtures carry exactly the six mood descriptors, so that sentence is about
the golden gate, not the API. Not a defect.

### SHOULD-FIX 1 — CLOSED, all three sub-questions

```
:mood_hapy → MoodProbe::ConfigurationError | MoodProbe::Error? true | lists valid ids? true
  "unknown descriptor: mood_hapy; valid descriptors: valence_emomusic, arousal_emomusic, danceability, …"
:tempo     → MoodProbe::ConfigurationError | MoodProbe::Error? true | lists valid ids? true
String "bpm" still works → resolves to emit id "bpm"
```

Inside the hierarchy ✅ · lists valid ids ✅ · String ids still coerce ✅. `plan.rb:92-97` gives
`GRAPH_ALGORITHMS.fetch` the same treatment, naming the valid algorithms.

### SHOULD-FIX 2 — CLOSED. The YARD answers exactly the three questions I posed.

| My round-1 question | Documented answer | Behaviour verified |
| --- | --- | --- |
| does `Analysis#[]` raise or return nil? | *"`{#[]}` raises `KeyError` when the requested id is absent."* | raises `KeyError` ✅ |
| is `Scalar#value` always `Float`? | *"A scalar descriptor value. `{#value}` is always a finite `Float`."* | `Integer 1` → `Float` ✅ |
| is `Provenance#essentia_version` nil? | *"`essentia_version` is currently always `nil`; the backend does not yet report a build-unique Essentia version."* | `nil` ✅ |

Documenting the `KeyError` on `Analysis#[]` rather than changing it is the right call: the app's own
spec asserts that behaviour, and a Hash-like accessor raising `KeyError` is idiomatic. Every error class
also gained a line stating its *delivery* — "Returned in a batch, or raised by `Extractor#analyze`" —
which is the consumer-facing half of the contract and is accurate.

### SHOULD-FIX 3 — CLOSED, and the relocation is better than what I asked for

I asked for the constructor to stop rejecting self-hosted models. What landed also *keeps* the
restriction where it belongs. Verified both directions:

```
Model.new(source_url: "https://models.example.org/mine.pb") → ACCEPTED
Registry.new(models: [that], descriptors: [])                → OK

ModelStore.validate_download_uri!(…)
  plain http                → rejected (requires HTTPS)
  suffix  essentia.upf.edu.evil.test → rejected (host not allowed)
  userinfo essentia.upf.edu@evil.test → rejected (host "evil.test" not allowed)
  third-party models.example.org      → rejected (host not allowed)
  legitimate essentia.upf.edu         → ACCEPTED   (passing control)
```

This is precisely §C.2 rule 5's shape — *"Custom URLs are never auto-fetched — an operator supplies a
local artifact plus a digest"* — now implemented rather than deferred: a consumer can **describe** a
self-hosted model and have its digest verified, and the gem will **not fetch** from an unvetted host.
`BackendError` is a `FatalError` (verified), so a disallowed host aborts rather than skipping a track.
Basename, HTTPS, sha256 and byte_length remain construction invariants.

### SHOULD-FIX 5 — CLOSED. The record is honest and invents nothing.

`golden/PROVENANCE.md:3-4`:

> - Origin: commit `c74a15b…` updated the four JSON files in this directory.
> - Historical limitation: **that commit does not record** the command, model directory, model digests,
>   container image, CPU, or other execution details used to produce those bytes. **Its generation
>   method is therefore unrecorded.**

That is the `principal-golden-provenance.md` Q4 instruction followed literally, and it follows the
`baseline_v0_1_0/PROVENANCE.md` precedent of recording the unrecorded. It does **not** back-fill a
provenance it cannot support, and `:8-16` gives a deliberate regeneration procedure with an instruction
to commit the reason and the full environment alongside the diff. Nothing to add.

---

## New findings — both in the newly added README sections

### SHOULD-FIX A — the backend contract states the return-not-raise rule for batch only, and the single-file path needs it too

**Where.** `README.md:38-43`:

> A backend provides `preflight_environment!`, `preflight_plan!(plan)`, and `analyze(path, plan:)`. It
> **may also** provide `analyze_all(paths, plan:)`… **A batch result** preserves input order and returns
> a `MoodProbe::TrackError` instance in the corresponding result position… it does not raise that error.

**Why it is wrong.** The return-not-raise rule is not batch-specific — it is how the extractor detects a
per-track failure on *both* paths. `Extractor#analyze_all` (`extractor.rb:73-90`) routes the batch branch
and the single-call branch through the *same* `result_for_outcome`, which recognises a per-track failure
**solely by return value** (`extractor.rb:111-115`, `return Result.new(path:, error: outcome) if
outcome.is_a?(TrackError)`). And `analyze_all` has **no `rescue` for `TrackError`** — the only rescue in
the file is `MalformedOutputError` inside `result_for_values` (`extractor.rb:107`), which covers values
the *builder* rejects, not exceptions raised by the backend.

**Concrete failure scenario.** A consumer writes the minimal backend the README sanctions — three
methods, no `analyze_all` — and raises `UnreadableAudioError` from `analyze` for a corrupt file. Nothing
in the README told them not to; `errors.rb`'s own YARD reinforces the idea by describing these errors as
"raised by `Extractor#analyze`". Calling `extractor.analyze_all(twenty_paths, descriptors:)`, the
exception propagates out uncaught: **one undecodable file aborts the whole batch** instead of returning
nineteen successful `Result`s and one error `Result`. And single-file use looks fine, because
`Extractor#analyze` re-raises anyway — so the defect is invisible until the first batch, the worst
discovery order.

**Why now.** Item 9 replaced `backend.is_a?(Backends::EssentiaPython)` with
`backend.respond_to?(:analyze_all)`, which is what makes a third-party backend first-class, and this
README section is what invites one. The door and the incomplete instruction shipped together.

**Fix.** One clause: state that **both** `analyze` and `analyze_all` return a `TrackError` rather than
raising it, and that only `Extractor#analyze` converts it back into a raise for its caller.

### SHOULD-FIX B — "Adding an algorithm" merges two disjoint extension paths into one four-site list

**Where.** `README.md:47-52` gives a single list: `Planner::GRAPH_ALGORITHMS`, plus the
`_GRAPH_ALGORITHMS` enum, the parameter types/domains/defaults tables, and `build_pipeline`.

**Why it is wrong.** The code has **two separate paths**, and neither has four sites:

| | Graph algorithm (model-backed) | Standalone algorithm (e.g. `RhythmExtractor2013`) |
| --- | --- | --- |
| Ruby | `Planner::GRAPH_ALGORITHMS` (`plan.rb:26-29`), reached only from `graph_plan` for `FromModel` rows (`:79` → `:92-97`) | **none** — the name is a free String on the registry row (`registry.rb:280`); `algorithm_plan` (`plan.rb:99-103`) forwards `definition.name` verbatim and never consults `GRAPH_ALGORITHMS` |
| Python enum | `_GRAPH_ALGORITHMS` (`:19`), checked at `:147` | `_ALGORITHM_PARAMS` (`:23`), checked at `:194` |
| Param tables | **not applicable** — graph params are rejected unconditionally at `:149-150` (`if graph.get("params"): raise "params are not allowed"`) | `_ALGORITHM_PARAM_DOMAINS` (`:36`), `_ALGORITHM_PARAM_DEFAULTS` (`:46`) |
| Executor | `build_pipeline` (`:370`) | `build_pipeline` (`:370`) |
| **Sites** | **three** | **four, and `Planner::GRAPH_ALGORITHMS` is not one of them** |

**Failure scenario (a) — wrong file.** A consumer adds a standalone Essentia algorithm, say
`KeyExtractor`. Following `README.md:48` they add `key_extractor: "KeyExtractor"` to
`Planner::GRAPH_ALGORITHMS`. That constant is never consulted for `FromAlgorithm` rows, so the edit is
dead code; their plan is then rejected by Python at `:194` against `_ALGORITHM_PARAMS`, one of four
tables the README lumps together. They have edited the wrong file in the wrong repository layer and are
pointed at the right one only by an error message.

**Failure scenario (b) — polluted capability surface.** A consumer adds a graph algorithm and, following
"the parameter types/domains/defaults tables", adds an `_ALGORITHM_PARAMS` entry keyed by it. Default-deny
is **not** defeated — I verified `:149-150` rejects graph `params` unconditionally, regardless of the
table — but `capabilities()` (`:58-62`) computes `sorted(_GRAPH_ALGORITHMS | _ALGORITHM_PARAMS.keys())`,
so the stray key is **advertised as an available algorithm while being unreachable as a standalone one**.
G11 cross-checks that advertised list against the registry, so the consumer has degraded the gem's
capability contract by following its own README.

**Fix.** Split the section into the two paths with their real site lists, and say plainly that graph
algorithms take no `params` — which is a security property worth stating in the extension guide rather
than leaving to be discovered.

---

## Restated, still open, not addressed this round (both NITs from round 1)

- **NIT 2** — `reduction: :mean_over_frames` is the only supported reduction (`registry.rb:200`, asserted
  as the sole permitted value at `python/mood_probe_extract.py:196`). A consumer wanting max-over-frames
  must patch the gem. The plan's `emit` already carries `reduce`, so the wire format is ready.
- **NIT 3** — descriptor-id naming is inconsistent: `valence_emomusic`/`arousal_emomusic` encode their
  model, `danceability`/`mood_acoustic`/`mood_relaxed`/`mood_happy` do not, though each is equally
  model-specific. Now *more* visible, not less, because `mood-probe descriptors` prints the list. Ids are
  public API and cheap to align only before publication.

## Regression hunt — I looked specifically, and found none in code

The two changes most likely to regress, probed directly:

1. **Host allowlist moved out of `Model.new`.** Risk: the manifest's own rows lose their host guard.
   **They do not** — `spec/registry_spec.rb:151` still asserts every default row's `source_url`
   `start_with("https://essentia.upf.edu/")`, and the download path re-checks **per hop** (the redirect
   loop calls `ModelStore.validate_download_uri!` on each `uri`), preserving the per-hop property from
   the slice-2 review. All three bypasses I tested in slice 2 are still rejected, with a passing control.
2. **`respond_to?(:analyze_all)` replacing the concrete-class check.** Risk: a partially-implemented
   backend silently routed down the batch branch. Behaviourally this only widens which backends get
   batching, `respond_to?` excludes private methods, and the suite is green at 184. The *documentation*
   consequence is SHOULD-FIX A, not a code regression.

Also checked and clean: `models fetch` / `models verify` still work without `--descriptors` (verified —
`models verify` against a missing directory returns the expected `missing models directory` message), and
`Extractor.new` construction moved inside the `analyze` branch so a missing `--descriptors` now aborts
before any backend is built.

---

## Evidence

**Range:** `848f6894a6022b5a32ae2b6b0c6898ac84986fa0..036c797f87e8a490dbcc676da0e7bfce8e0fb298`.
All git commands run as `git -C /Users/lukeolson/projects/gems/mood_probe`.

```
$ git status --porcelain                → (empty)
$ git rev-parse HEAD                    → 036c797f87e8a490dbcc676da0e7bfce8e0fb298
$ git rev-parse 'v0.2.0^{}'             → 848f6894a6022b5a32ae2b6b0c6898ac84986fa0   (not moved)
$ git tag                               → v0.1.0, v0.2.0   (none created)
$ grep -n VERSION lib/mood_probe/version.rb → "0.2.1"
$ git diff --stat 848f6894..036c797     → 21 files, 327 insertions(+), 31 deletions(-)
$ bundle exec rspec                     → 184 examples, 0 failures
$ bundle exec rubocop                   → 48 files inspected, no offenses detected
```

Rulings verified by execution (`bundle exec ruby -Ilib -rmood_probe -e …`):
```
SF1  :mood_hapy → MoodProbe::ConfigurationError, is_a?(MoodProbe::Error)=true, message lists valid ids
     :tempo     → same ;  "bpm" (String) → resolves, emit id "bpm"
SF2  Scalar#value from Integer 1 → Float ;  Analysis#[](:nope) → KeyError ;
     Provenance#essentia_version → nil
SF3  Model.new(source_url: "https://models.example.org/mine.pb") → ACCEPTED
     Registry.new(models: [it], descriptors: []) → OK
     validate_download_uri!: http → rejected ; …edu.evil.test → rejected ;
       …edu@evil.test → rejected (host "evil.test") ; models.example.org → rejected ;
       essentia.upf.edu → ACCEPTED (control)
     BackendError.ancestors.include?(FatalError) → true
CLI  `mood-probe descriptors` → prints nine ids, exit 0
     `mood-probe --models-dir /tmp/nonexistent-models models verify` → "missing models directory: …"
```

Code read for the two new findings: `lib/mood_probe/extractor.rb:73-90`, `:104-115`;
`lib/mood_probe/plan.rb:26-29`, `:76-97`, `:99-103`; `lib/mood_probe/registry.rb:275-283`;
`python/mood_probe_extract.py:19`, `:23`, `:36`, `:46`, `:58-62`, `:147`, `:149-150`, `:194`, `:331`,
`:352`, `:370`; `exe/mood-probe:24-48`; `spec/registry_spec.rb:151`; and `README.md` in full.

**Verified vs believed.** Every ruling above rests on a command and its output, or on a code line I
read — those I **verified**. Two statements are **belief**, flagged as such: the failure scenarios in
SHOULD-FIX A and B describe what I judge a consumer following the README would do, which is a judgement
about behaviour rather than a measurement — though in both cases the code facts the scenarios turn on
(no `TrackError` rescue in `analyze_all`; `GRAPH_ALGORITHMS` unreachable from `FromAlgorithm` rows;
`capabilities()` unioning `_ALGORITHM_PARAMS.keys()`) are each verified.

**Read-only confirmed.** No file in either repository was modified, staged or committed except this
report. All probes were `git`/`grep`/`ls` reads and `bundle exec ruby -e` / `exe/mood-probe` invocations
against the committed tree; the `models verify` probe pointed at a non-existent directory and wrote
nothing.

VERDICT: APPROVE-WITH-FINDINGS
