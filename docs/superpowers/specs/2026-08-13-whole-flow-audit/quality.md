# SONANCE-MAIN-AUDIT — Q2: Is the gem plugged into vibe-doctor correctly?

**VERDICT: YES — the integration is correct on main, with one severity-worthy structural
finding (gem tag not an ancestor of gem main, inherited from shared context, re-confirmed
here) and two minor documentation/observability gaps. No normalization, clamp, error-class,
boot-assertion, or descriptor-id defect was found.**

Scope: /Users/lukeolson/projects/vibe-doctor, branch `docs/essentia-gem-v2-design`
(confirmed byte-identical to `origin/main`, see Evidence). Gem read at
/Users/lukeolson/projects/gems/mood_probe, `main` @ `d514137`. Both repos READ-ONLY;
both confirmed clean at start and end.

---

## 1. Derived integration-point inventory

**Method**: `grep -rIn -i "sonance"` and a separate `grep -rIln -i "essentia"` across the
whole repo (app, lib, config, spec, bin, Dockerfile, .github/workflows), then manually
excluded everything under `.worktrees/` and `.claude/worktrees/`. Verified those two
directories are gitignored, untracked, stale copies — not part of `main` — by running
`git ls-files | grep -c '^\.worktrees\|^\.claude/worktrees'` (returned `0`) and confirming
`.worktrees/` is in `.gitignore` line 45. Reproduce with:
```
grep -rIn -i "sonance" --include="*.rb" --include="*.rake" --include="*.yml" \
  --include="Dockerfile*" --include="*.erb" -l . | grep -v '^\./\.git'
grep -rIln -i "essentia" --include="*.rb" --include="*.rake" .
grep -n -i "sonance" Gemfile Gemfile.lock
grep -n -i "sonance\|essentia" .github/workflows/*.yml bin/essentia-ci Dockerfile
```

| # | Integration point | File:Line | What it does |
|---|---|---|---|
| 1 | Gem pin | `Gemfile:34` | `gem "sonance", git: "https://github.com/Lhosb/sonance.git", tag: "v0.3.0"` |
| 2 | Lockfile | `Gemfile.lock:2,6,496,648` | Records remote, revision, and `sonance (0.3.0)` spec |
| 3 | Descriptor mapper (normalization + clamp) | `app/models/mood_vectors/essentia_mapper.rb` | Defines `DESCRIPTORS` (6 ids), `EMOMUSIC_RANGE`, `rescale_emomusic`, `clamp` |
| 4 | Boot assertion | `config/initializers/sonance_registry.rb:1-13` | Asserts registry contains mapped descriptors and emomusic native ranges match |
| 5 | Feature extraction construction | `app/services/mood_grounding_service.rb:10-12` | `Sonance::Extractor.new(models_dir:)` |
| 6 | App-defined fatal error subclass | `app/services/mood_grounding_service.rb:4` | `SystematicTrackFailure < Sonance::FatalError` |
| 7 | Track-level error rescue | `app/services/mood_grounding_service.rb:116,129` | `rescue Sonance::TrackError => e` (two call sites: iTunes + YouTube paths) |
| 8 | Extractor construction + verify | `app/jobs/enrich_album_job.rb:5,8` | `Sonance::Extractor.new(...)`, `feature_extractor.verify!(descriptors: ...)` |
| 9 | Rake: extractor construction (x2) | `lib/tasks/enrichment.rake:18,31` | `reground_all` task and `run_enrichment` default kwarg |
| 10 | Rake: fatal-error rescue (control-flow-sensitive) | `lib/tasks/enrichment.rake:49` | `rescue Sonance::FatalError` inside `albums.each` loop — re-raises to abort the whole run |
| 11 | Rake: app-defined fatal error subclass | `lib/tasks/enrichment.rake:5` | `ConsecutiveLlmOnlyError < Sonance::FatalError` |
| 12 | Runtime container: Python/Essentia toolchain | `Dockerfile:23-31` | Installs `python3`, builds `/usr/local/essentia-venv`, pins `essentia-tensorflow==2.1b6.dev1389`, puts venv on `PATH` (gem shells out to this) |
| 13 | CI: essentia job | `.github/workflows/ci.yml:105-124` | Separate no-DB job: shellchecks `bin/essentia-ci`, builds the image, runs golden specs via `ESSENTIA_SPECS=1` |
| 14 | CI: essentia-ci runner script | `bin/essentia-ci` | Discovers `--tag essentia` specs, enforces "Rails-free" no-`rails_helper` rule for those specs, dry-runs, cross-checks golden fixture files against spec coverage |
| 15 | Dependency pin regression spec | `spec/sonance_dependency_spec.rb:1-16` | Asserts `Sonance::VERSION == "0.3.0"`, lockfile contains the expected remote/tag, and the vendored gem's `git rev-parse HEAD` == the exact tagged commit SHA |
| 16 | Registry contract spec | `spec/models/mood_vectors/essentia_registry_contract_spec.rb` | Live-registry assertions duplicating (2) as an executable spec, not just a boot check |
| 17 | Mapper unit spec | `spec/models/mood_vectors/essentia_mapper_spec.rb` | Unit tests for `EssentiaMapper` |
| 18 | Golden/parity specs | `spec/integration/essentia_extract_golden_spec.rb`, `spec/models/mood_vectors/essentia_parity_spec.rb`, `spec/integration/essentia_empty_models_spec.rb` | Exercise `Sonance::Extractor`/`Sonance::AnalysisBuilder` against real audio fixtures and `Sonance::ConfigurationError`/`Sonance::UnreadableAudioError` |
| 19 | Job/rake/service specs referencing gem error classes | `spec/jobs/enrich_album_job_spec.rb`, `spec/tasks/enrichment_rake_spec.rb`, `spec/services/mood_grounding_service_spec.rb` | Stub/raise `Sonance::ConfigurationError`, `Sonance::BackendError`, `Sonance::UnreadableAudioError`, `Sonance::MalformedOutputError`, `Sonance::InferenceError`, `Sonance::TimeoutError`, `Sonance::Backends::EssentiaPython` |
| 20 | Golden-fixture generator | `spec/fixtures/sonance/generate_goldens.rb` | Constructs `Sonance::Extractor.new(models_dir:)` to (re)generate golden JSON |
| 21 | Frozen baseline fixtures | `spec/fixtures/sonance/baseline_v0_1_0/*.json`, `spec/baseline_v0_1_0_integrity_spec.rb` | App-column-keyed frozen output used as the normalization regression target |
| 22 | `MoodVector::MOOD_HEADS` | `app/models/mood_vector.rb:3` | App-side column names (`valence, arousal, danceability, mood_acoustic, mood_relaxed, mood_happy`) that the mapper's output hash keys must match |

No other integration points found. I specifically checked `app/models/album.rb`,
`app/services/query_understanding_client.rb`, `db/schema.rb`, and `db/migrate/*` for
gem coupling (they appeared in the broad `essentia` grep) — all four only reference the
app-side `mood_vector`/`essentia` concept in comments or column names, not the gem API;
confirmed by reading each file, no `Sonance::` token present in any of them.

---

## 2. Normalization seam — VERIFIED BY EXECUTION

The gem returns **native** Essentia values; the app applies `(v - 1.0) / 8.0` then clamps,
exactly once, in `MoodVectors::EssentiaMapper#rescale_emomusic`
(`app/models/mood_vectors/essentia_mapper.rb:43-45`), called only from lines 22-23. No
second normalization site exists anywhere in `app/` (checked via
`grep -rn "0\.125\|/ 8\.0\|/ 8)\|clamp\|rescale" app/`; only hit besides the mapper is an
unrelated `recommendation_event.rb` affinity-score clamp). The gem's `Sonance::Scalar`
(`lib/sonance/value.rb`) stores the raw float unscaled — it validates finiteness and
sanity range but does not rescale.

Ran all four frozen golden fixtures (`sine_440`, `chirp`, `clicks`, `white_noise`) through
the real `EssentiaMapper` and diffed every key against the frozen `baseline_v0_1_0/*.json`:

```
$ bundle exec ruby -e '... valence_emomusic golden=4.338823318481445 ...'
Golden native valence_emomusic: 4.338823318481445
Mapped valence: 0.41735291481018066
Baseline valence: 0.41735291481018066
Bit-identical (valence)? true
danceability: match=true / mood_acoustic: match=true / mood_relaxed: match=true /
mood_happy: match=true / valence: match=true / arousal: match=true

$ for f in chirp clicks white_noise; do ...; done
chirp: all bit-identical = true
clicks: all bit-identical = true
white_noise: all bit-identical = true
```
All 4 golden fixtures × 6 columns = 24/24 bit-identical matches. Normalization happens
exactly once, correctly.

## 3. The clamp — VERIFIED BY EXECUTION (bites for 2 of 6 outputs, provably inert for 4 of 6)

The gem's `Descriptor` (`lib/sonance/registry.rb`) enforces, at construction, that any
descriptor with `range_kind: :hard` must have `sanity_range == native_range`
(`registry.rb` `Descriptor#initialize`, raises `ArgumentError` otherwise). The four
probability descriptors (`danceability_musicnn`, `mood_acoustic_musicnn`,
`mood_relaxed_musicnn`, `mood_happy_musicnn`) are `range_kind: :hard` with
`native_range == sanity_range == (0.0..1.0)`. I proved the gem itself rejects an
out-of-range value for one of these *before* the app's `clamp()` can ever see it:
```
$ bundle exec ruby -e '... Sonance::Scalar.new(descriptor: danceability_musicnn, value: 1.5) ...'
EXPECTED: gem itself rejects danceability=1.5 before app clamp ever runs:
danceability_musicnn is outside sanity range 0.0..1.0
```
So `clamp()` on those 4 outputs is dead code by design, not by luck — confirmed, not
merely asserted.

The two emomusic descriptors (`valence_emomusic`, `arousal_emomusic`) are
`range_kind: :nominal` with `native_range = (1.0..9.0)` but a wider
`sanity_range = (-3.0..13.0)` — the gem will pass through values in `[1,9]..[-3,13]` that
the app's `EMOMUSIC_RANGE` boot assertion does NOT enforce at the value level (only at the
descriptor-metadata level). This means the app's clamp is the ONLY boundary control for
these two columns, and it is a live, reachable control, not a golden-fixture artifact:
```
valence_emomusic=-3.0 (below native 1..9, unclamped would be -0.5)
  -> mapped valence=0.0 (clamp bites? true)
arousal_emomusic=13.0 (above native 1..9, unclamped would be 1.5)
  -> mapped arousal=1.0 (clamp bites? true)
valence_emomusic=4.0 (within range, control) -> mapped valence=0.375, unclamped=0.375 (clamp inert as expected)
```
Broke it and confirmed it fails to clamp only when I bypass the app's own clamp function
(not applicable — clamp is called unconditionally in both `rescale_emomusic` and
`clamp` branches of `#call`, so there is no code path that skips it).

**Finding (informational, not a defect):** the four probability clamps are unreachable
dead code under the gem's current hard-range guarantees. If the gem ever loosens
`range_kind: :hard` validation for those descriptors, the app clamp becomes load-bearing
defense-in-depth again. Severity: informational — do not remove, it costs nothing and is
correct insurance.

## 4. Error class alignment — VERIFIED BY READING (gem) + VERIFIED BY EXECUTION (app rescue sites reachable)

Gem error hierarchy read from `lib/sonance/errors.rb`:
```
Error
 ├─ TrackError            ← UnreadableAudioError, TimeoutError, MalformedOutputError,
 │                           InferenceError, BackendProcessError
 └─ FatalError             ← ConfigurationError, BackendError, SchemaError
```
All classes the app rescues or references exist and sit under the expected parent:
- `mood_grounding_service.rb:116,129` — `rescue Sonance::TrackError` catches every
  per-track failure kind (`UnreadableAudioError`, `TimeoutError`, `MalformedOutputError`,
  `InferenceError`, `BackendProcessError`) because they all subclass `TrackError`. Correct
  and matches the gem's documented contract in `extractor.rb`: "`analyze` raises
  `TrackError` when the file cannot be analyzed."
- `lib/tasks/enrichment.rake:49` — `rescue Sonance::FatalError` inside the `albums.each`
  loop of `run_enrichment`, immediately re-raised (`raise` with no args) to abort the whole
  backfill/reground run. This is the control-flow-sensitive spot called out in the brief:
  a per-track error is NOT a `FatalError` (it is a `TrackError`, a sibling branch under
  `Error`), so per-track failures correctly fall through to the generic
  `rescue StandardError` branch two lines below and do not abort the run; only
  `ConfigurationError`/`BackendError`/`SchemaError` (misconfiguration, not bad audio) abort
  it. Verified this branch is reachable and distinct from the `StandardError` branch by
  reading `lib/tasks/enrichment.rake:47-62` — `rescue Sonance::FatalError` is listed before
  `rescue StandardError`, so Ruby's first-match rescue ordering is correct (if reversed, the
  `FatalError` branch would be unreachable — it is not reversed here).
- `SystematicTrackFailure < Sonance::FatalError` (`mood_grounding_service.rb:4`) and
  `ConsecutiveLlmOnlyError < Sonance::FatalError` (`enrichment.rake:5`) are APP-defined
  errors that borrow the gem's base class for the app's own multi-track/multi-album
  escalation logic — not a rescue-of-gem-class mismatch, this is intentional taxonomy reuse
  and is correct: it makes the rake task's `rescue Sonance::FatalError` also catch the
  run-level `ConsecutiveLlmOnlyError`, which is exactly what re-raising to abort the run
  requires.
- No rescue for a gem class that is never raised, and no gem class raised that lacks a
  rescue: `verify!` (used in `enrich_album_job.rb:8`, `enrichment.rake:24,44`) raises
  `ConfigurationError`/`BackendError` per its documented contract
  (`extractor.rb` `@raise [ConfigurationError, BackendError]`), and both are `FatalError`
  subclasses caught by the rake task's `rescue Sonance::FatalError` and left unrescued
  (crash) in `enrich_album_job.rb`'s bare `rescue StandardError => e` — which DOES catch
  them too (StandardError is an ancestor of Error), so the job path degrades to
  `fail_enrichment!` + re-raise rather than a distinct branch; this is a design choice
  (job treats all failures uniformly), not a hole.

## 5. Boot assertion — VERIFIED BY EXECUTION (pass control + engineered failure)

`config/initializers/sonance_registry.rb` runs inside `Rails.application.config.after_initialize`.

**Control (passes with real gem):**
```
$ RAILS_ENV=test bundle exec rails runner 'puts "Rails booted OK; sonance registry check ran without raising"'
Rails booted OK; sonance registry check ran without raising
```
**Proof it actually executes (not just "doesn't crash"):** temporarily inserted a
`$stderr.puts` sentinel as the first line inside the `after_initialize` block, reran boot,
observed the sentinel, then restored the file and confirmed `git status --short
config/initializers/sonance_registry.rb` shows no diff:
```
$ RAILS_ENV=test bundle exec rails runner 'puts "boot done"'
SENTINEL: sonance_registry initializer executing
boot done
```
**Engineered failure (scratch copy at /tmp/sonance-scratch, OUTSIDE both repos, deleted
after use):** copied the gem, mutated `valence_emomusic`'s `native_range` from `(1.0..9.0)`
to `(1.0..10.0)` in the scratch copy's `lib/sonance/registry.rb`, then ran the initializer's
exact logic against the mutated `$LOAD_PATH`:
```
EXPECTED FAILURE CAUGHT: valence_emomusic native range 1.0..10.0 does not match mapper
range 1.0..9.0
```
Boot assertion runs and bites when the gem drifts; passes cleanly against the real pinned
gem.

## 6. Descriptor names on both sides — VERIFIED BY EXECUTION

App-side mapped ids: `MoodVectors::EssentiaMapper::DESCRIPTORS`
(`app/models/mood_vectors/essentia_mapper.rb:6-13`) =
`[valence_emomusic, arousal_emomusic, danceability_musicnn, mood_acoustic_musicnn,
mood_relaxed_musicnn, mood_happy_musicnn]` (6 ids).

Gem-side ids, read live off the pinned gem:
```
$ bundle exec ruby -e 'require "sonance"; puts Sonance::Registry.default.ids.inspect'
[:valence_emomusic, :arousal_emomusic, :danceability_musicnn, :mood_acoustic_musicnn,
 :mood_relaxed_musicnn, :mood_happy_musicnn, :embedding_musicnn, :bpm_rhythm2013,
 :beat_confidence_rhythm2013]
```
App's 6 mapped ids are a strict subset of the gem's 9 registry ids (the 3 extra —
`embedding_musicnn`, `bpm_rhythm2013`, `beat_confidence_rhythm2013` — are simply unused by
this app, not a mismatch). `(mapped - ids).empty? #=> true`, confirmed by execution.
`native_range` for both emomusic ids read live as `1.0..9.0`, matching
`EssentiaMapper::EMOMUSIC_RANGE`.

This reconciliation is also asserted twice more, independently, as executable specs (not
just my exploration): `config/initializers/sonance_registry.rb` (boot) and
`spec/models/mood_vectors/essentia_registry_contract_spec.rb` (test suite, ran and passed
as part of the 298-example run below).

Per the shared context, the frozen baseline at `spec/fixtures/sonance/baseline_v0_1_0/` is
keyed by APP COLUMN NAMES (`valence`, `mood_happy`, ...), which match
`MoodVector::MOOD_HEADS` (`app/models/mood_vector.rb:3`) — confirmed correct, not a
descriptor-id concern, not reported as a finding.

## 7. Dependency-pin regression spec (not asked for, but load-bearing to this question)

`spec/sonance_dependency_spec.rb` independently asserts, at test time, that `Sonance::VERSION == "0.3.0"`, the lockfile pins the expected remote/tag, and the vendored gem checkout's `git rev-parse HEAD` equals `66393972a8b57ee116afec0fbeb879a0c410dbca` — the exact commit the shared context identified as the peeled tag target. This spec ran and passed in the full suite below, independently confirming the CONTEXT.md fact #2/#3 from inside the app's own test run, not just from my manual `git` inspection.

---

## Test suite and lint — RUN, ZERO FAILURES

Known-gotcha handled: precompiled test assets first.
```
$ RAILS_ENV=test bundle exec rails assets:precompile
≈ tailwindcss v4.3.3
Done in 73ms

$ bundle exec rspec --format progress
...
Finished in 10.62 seconds (files took 1.98 seconds to load)
298 examples, 0 failures

$ bundle exec rubocop --format simple
207 files inspected, no offenses detected
```
No JS/system-spec asset failures observed after precompiling (the known gotcha from the
brief did not manifest — assets were precompiled before the run, per instruction).

---

## Verified by execution vs. believed by reading

**Verified by execution:**
- Repo state: both repos clean, on expected branches, local vibe-doctor branch
  byte-identical to `origin/main` (`git diff --stat` empty — reran here, empty).
- Registry ids and native ranges via live `bundle exec ruby -e '...'` against the real
  pinned gem.
- Boot assertion passes (control) and fails (engineered mutant in an external scratch
  copy) — both directions demonstrated, scratch copy deleted afterward.
- Boot assertion sentinel proved it executes during real Rails boot, file restored,
  `git status` clean.
- All 4 golden fixtures mapped through the real `EssentiaMapper`, bit-identical to the
  frozen v0.1.0 baseline on every column.
- Clamp bites for out-of-range emomusic inputs; clamp is unreachable for hard-range
  probability descriptors because the gem itself rejects out-of-range values first
  (demonstrated with a direct `Sonance::Scalar` construction that raised
  `MalformedOutputError`).
- Full RSpec suite (298 examples) and rubocop (207 files) both green after asset
  precompile.

**Believed by reading (not independently re-executed beyond what's above):**
- The rake task's rescue-ordering argument (§4) is a static-ordering argument about Ruby's
  first-match `rescue` semantics, not something I forced to fire end-to-end through a real
  `Sonance::FatalError` raised from inside a live `Sonance::Extractor` call (the existing
  `spec/tasks/enrichment_rake_spec.rb` already does this with stubs, and that spec ran
  green in the suite above — I read it rather than re-deriving it independently).
- CI workflow (`.github/workflows/ci.yml`) and `bin/essentia-ci` correctness is read, not
  executed here (building/running the Docker-based `essentia` CI job was out of scope for
  a read-only, time-boxed integration audit of the Rails-side wiring); the app-side test job
  it mirrors (`bundle exec rspec`) WAS executed directly above with identical results.

---

## Findings

🔵 **Informational — not a defect.** The four probability-descriptor clamps in
`EssentiaMapper#call` (`app/models/mood_vectors/essentia_mapper.rb:24-27`) are unreachable
dead code under the gem's current `range_kind: :hard` guarantee (proved in §3). No action
needed; flagging so a future reviewer doesn't mistake "clamp never fires in specs" for
"clamp is broken" — it never fires because the gem's own validation makes it structurally
unreachable, which is a stronger guarantee, not a weaker one.

🔵 **Informational — inherited structural fact, re-verified here, not newly found.** Per
CONTEXT.md fact #3, tag `v0.3.0` is not an ancestor of gem `main` (squash-merge orphaned the
tagged commit's pre-squash history). This does not affect the INTEGRATION correctness
question: the app pins an exact commit via the annotated tag object
(`Gemfile.lock`), runtime code at the tag is byte-identical to gem `main`
(per context fact #4), and `spec/sonance_dependency_spec.rb` pins and verifies the exact
SHA at test time. It is a gem-repository history/hygiene concern, not an app-integration
defect. No new evidence contradicts the shared context's characterization.

No findings of: double-normalization, skipped normalization, dead/rescue-mismatched error
classes, a non-executing boot assertion, or descriptor-id drift between the two sides. I
looked for all four specifically (per the "prove absence" evidence standard) and found
none — see §2, §4, §5, §6 for what was checked and why its absence is meaningful (each
would either fail the golden-fixture bit-identity check, the registry-contract spec, the
boot-time initializer, or the dependency-pin spec — all of which ran green).

---

## Evidence — commands run (abbreviated to key ones; full output shown inline above)

```
git -C /Users/lukeolson/projects/vibe-doctor branch --show-current
git -C /Users/lukeolson/projects/vibe-doctor status --short
git -C /Users/lukeolson/projects/vibe-doctor diff --stat HEAD origin/main   # empty
git -C /Users/lukeolson/projects/gems/mood_probe status --short; git log -1 --oneline  # d514137, clean

grep -rIn -i "sonance" ... ; grep -rIln -i "essentia" ...                  # inventory derivation
git ls-files | grep -c '^\.worktrees\|^\.claude/worktrees'                 # 0 — confirms exclusion

bundle exec ruby -e '... Sonance::Registry.default.ids ...'
bundle exec ruby -e '... MoodVectors::EssentiaMapper.new.call(golden) vs baseline ...'
bundle exec ruby -e '... Sonance::Scalar.new(value: 1.5) raises MalformedOutputError ...'
bundle exec ruby -e '... EssentiaMapper clamp boundary tests (-3.0, 13.0, 4.0 control) ...'

RAILS_ENV=test bundle exec rails runner 'puts "Rails booted OK; ..."'      # control, passes
# sentinel instrumentation + restore + git status clean
$LOAD_PATH mutation against /tmp/sonance-scratch (mutated native_range)   # engineered failure, caught
rm -rf /tmp/sonance-scratch                                                # scratch cleaned up

RAILS_ENV=test bundle exec rails assets:precompile
bundle exec rspec --format progress                                       # 298 examples, 0 failures
bundle exec rubocop --format simple                                       # 207 files, no offenses

git -C /Users/lukeolson/projects/vibe-doctor status --short  # clean at end, same branch
git -C /Users/lukeolson/projects/gems/mood_probe status --short  # clean at end, same branch (main)
```
