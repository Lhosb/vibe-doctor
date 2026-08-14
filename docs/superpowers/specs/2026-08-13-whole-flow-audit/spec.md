# SONANCE-MAIN-AUDIT — Q1 SPEC HALF

**VERDICT: REQUEST-CHANGES**

Scope: gem only, `/Users/lukeolson/projects/gems/mood_probe` at `main` = `origin/main` = `d514137`.
Question answered: *is the gem's stated contract true, complete, and consistent with its behavior?*

The contract is **substantially true**. The error taxonomy, demand-driven planning, registry
integrity, and the CHANGELOG migration table all survived independent execution. Two things break
the verdict: **a documented CLI command emits memory addresses instead of descriptor values at exit
0**, and **the spec that nominally covers it is vacuous by construction**. Separately, the
descriptor-id gate has a proven blind spot precisely in the rename scenario it exists to catch.

Blast radius note for the Principal: **the library API is correct and the app does not use the
CLI.** F1 does not threaten deployability; it is a contract-vs-behavior break on the gem's primary
documented CLI verb.

---

## FINDINGS

### F1 — HIGH — `sonance analyze` emits object inspect strings, not descriptor values

- **File:** `exe/sonance:46`, mechanism at `lib/sonance/value.rb:197-199`
- **Documented at:** `README.md:29`

`exe/sonance:46` is `puts JSON.pretty_generate(extractor.analyze(path, descriptors:).to_h)`.
`Analysis#to_h` (`value.rb:197-199`) returns `{Symbol => Sonance::Value}`. `Sonance::Value` and its
subclasses define no `to_json`/`as_json`/`to_h`, so `JSON` falls back to `Object#to_s`.

Actual output of the README's own command shape, run against a committed fixture:

```
$ ruby -Ilib exe/sonance --models-dir /tmp/nonexistent-models \
    --descriptors bpm_rhythm2013 analyze spec/fixtures/sonance/audio/sine_440.wav
{
  "bpm_rhythm2013": "#<Sonance::Scalar:0x000000011ff3f9d8>"
}
exit=0
```

The extraction itself is correct — only the serialization is lost. Same file, library API:

```
bpm_rhythm2013 => 110.60472869873047 (Sonance::Scalar)
beat_confidence_rhythm2013 => 2.2199807167053223 (Sonance::Scalar)
```

**Failure scenario:** any operator following `README.md:29` gets zero descriptor data, a
non-deterministic payload (the hex address changes every run, so the output is not even stable
enough to diff), and **exit code 0** — nothing signals failure. Piping this into `jq` or a
downstream tool yields a string where a float is expected. Affects all nine descriptors and every
value kind (`Scalar`, `Vector`, `Categorical`, `Series`); `Vector` would lose a 200-element
embedding the same way.

**Severity rationale:** documented command, silent, total data loss, exit 0. CONTEXT records that a
previous release already shipped `analyze` broken. It is broken again, by a different mechanism.

### F2 — HIGH — the CLI `analyze` spec cannot observe F1; it stubs out the failing object

- **File:** `spec/cli_spec.rb:18-29` with `spec/support/recording_cli_analyze.rb:5-7`

The one example that exercises `analyze` output injects this stub:

```ruby
Sonance::Extractor.class_eval do
  define_method(:initialize) { |**options| @options = options }
  define_method(:analyze) do |path, descriptors:|
    Data.define(:path, :descriptors).new(path:, descriptors:)
  end
end
```

The stub returns a `Data` object whose `to_h` is `{path: String, descriptors: Array}` — natively
JSON-serializable. The real return value is `Analysis`, whose `to_h` values are `Sonance::Value`
objects. **The spec asserts on the one object shape that cannot exhibit the bug.** It verifies
argument plumbing only; it makes no assertion about any descriptor value. This is why a 194-example
suite is green with a broken documented command.

This is the "gates need a non-vacuity floor" failure mode: the gate runs, passes, and proves nothing
about the thing it appears to cover.

### F3 — MEDIUM-HIGH — descriptor-id gate: a wholly-stale `%i[…]` array is invisible

- **File:** `spec/descriptor_id_integrity_spec.rb:27`

```ruby
next unless ids.any? { |id| known_descriptor_ids.include?(id) } || prefix.match?(descriptor_context)
```

A `%i[…]` array is inspected only if **at least one id in it is already valid**, or the preceding 80
characters contain `descriptor`/`DESCRIPTORS`. Therefore an array in which *every* id is stale is
skipped entirely. **A rename makes every id in a list stale simultaneously** — the gate is weakest
in exactly the scenario it was written for, and this matches the recorded history of stale ids
shipping twice.

Proven by controlled injection into a scratch clone (below). Three files, one gate run:

| injected into a **scanned** file | gate result |
|---|---|
| `SOME_SET = %i[bpm_rhythm2013 totally_bogus_id]` (mixed) | **CAUGHT** |
| `DEFAULT_DESCRIPTORS = %i[mood_happy danceability]` (stale, prefix says DESCRIPTORS) | **CAUGHT** |
| `LEGACY_SET = %i[mood_happy danceability musicnn_embedding]` (all stale, neutral name) | **MISSED — 0 failures** |

The third case is three real pre-0.3 ids from the CHANGELOG's own migration table, in a file the
gate globs, and the gate reports clean.

**What the gate actually enforces vs. what a reader assumes:**

| A reader assumes | It actually does |
|---|---|
| "repository descriptor ids" — repo-wide | 47 of 89 tracked files (see F4) |
| any stale id is caught | only two literal shapes: `%i[…]`/`%w[…]` and `descriptors: […]` |
| stale ids are caught | a list is only examined if it already contains a *valid* id, or the word "descriptor" appears within 80 preceding chars |
| bare `:id`, hash keys, `fetch(:id)`, string keys | not matched at all |

### F4 — MEDIUM — gate file coverage is 47 of 89 tracked files

- **File:** `spec/descriptor_id_integrity_spec.rb:2-9`

Globs are `lib/**/*.rb`, `spec/**/*.rb`, `script/**/*.rb`, `exe/*`, `.github/workflows/*.yml|yaml`.
Unscanned: `python/sonance_extract.py`, **every JSON fixture** (`golden/`, `baseline_v0_1_0/`,
`plans/`), `README.md`, `CHANGELOG.md`, `Dockerfile.essentia`, `Gemfile*`, `Rakefile`, the gemspec.

Proven by injection (all green on the descriptor gate):

- stale ids appended to `python/sonance_extract.py` → gate green
- `"bpm_rhythm2013"` → `"bpm_STALE_ID"` in `spec/fixtures/sonance/plans/algorithm_only.json` → gate green
- stale ids appended to `README.md` → gate green

**Two honest mitigations I verified rather than assumed:**

1. The JSON **plan** fixtures are protected by a *different* mechanism. The full suite on the
   injected clone was `194 examples, 1 failure` — `planner_spec.rb` caught the plan mutation via
   fixture parity. So plans are covered; the gate just isn't what covers them.
2. `python/sonance_extract.py` **carries no hardcoded descriptor ids at all** (verified by grep for
   every registry producer suffix — zero hits). It treats `emit[].id` as an opaque pass-through
   string. The Python coverage gap is therefore **latent, not active**.

The genuinely unprotected surfaces are `README.md` and `CHANGELOG.md`: the Python and README
injections survived the *entire* 194-example suite, not just the gate.

### F5 — MEDIUM — the native-value contract rests on one README sentence, and no range can catch a violation

- **Only statement in the repo:** `README.md:3-6` — "Values are emitted in each descriptor's native
  range, declared on its registry row; normalization is the consumer's responsibility."
- **Absent from:** the YARD block on `Extractor#analyze` (`lib/sonance/extractor.rb:56-61`), which
  says only `@return [Analysis]`; absent from `CHANGELOG.md`; absent from the `Scalar` class doc
  (`value.rb:69`), which documents only "always a finite `Float`".

The README sentence is *unambiguous* where it appears — it is correct and clearly worded. The
problem is placement: a consumer reading the API docs at the call site never encounters it.

CONTEXT's factor-of-eight concern is real and I confirmed nothing would catch it. Using the
committed golden `valence_emomusic = 4.338823318481445` against the registry sanity range
`-3.0..13.0`:

```
native            = 4.338823318481445    in sanity -3.0..13.0? true
normalized once   = 0.41735291481018066  in sanity? true
normalized twice  = -0.07283088564872742 in sanity? true
```

**Failure scenario:** a consumer assuming normalized output, or an app that double-normalizes, stays
inside the sanity range at every stage. No exception, no warning, no clamp — values silently wrong
by 8×.

**Mitigation (verified):** the contract *is* machine-discoverable. `Value#native_range`, `#units`,
and `#range_kind` are reachable on returned values, and the registry declares
`valence_emomusic native=1.0..9.0`. A consumer who checks programmatically cannot get this wrong.
This is why F5 is MEDIUM, not HIGH.

### F6 — LOW — CHANGELOG documents only 0.3.0

`CHANGELOG.md` has a single `## 0.3.0` section, yet it points to tags `v0.1.0` and `v0.2.0` as "the
compatibility mechanism for consumers". Both tags exist. A consumer told to pin an older tag has no
record of what those releases contained.

### F7 — LOW / observation — misconfigured Python raises `ConfigurationError`, not `BackendError`

`errors.rb:25` documents `BackendError` as "raised when the backend environment … fails", but a
missing interpreter yields `ConfigurationError: unable to launch Python executable /nonexistent/python`.
Defensible either way (the user *did* configure a bad path) and both are `FatalError` subclasses, so
a consumer rescuing `FatalError` is unaffected. Noting for completeness, not asking for a change.

---

## VERIFIED BY EXECUTION

Everything below I ran and observed; output is pasted verbatim in EVIDENCE.

- **Descriptor id set derived from the registry itself** (not transcribed): exactly 9 ids, 6 models.
  I did not reuse CONTEXT's list; the derived set happens to match it.
- **CLI runs.** All subcommands and every argument-error branch: `descriptors`, `--help`, no-args,
  bogus command, `analyze` without `--descriptors`, `analyze` without FILE, `models` without
  subcommand. All exit correctly with correct messages.
- **F1** — `analyze` emitting `#<Sonance::Scalar:0x…>` at exit 0, and the same file yielding
  `110.60472869873047` through the library API.
- **F2** — read the stub; confirmed it returns a JSON-native `Data` object.
- **F3** — three-case injection matrix in a scratch clone; the wholly-stale array passes.
- **F4** — python/JSON/README injections; full-suite run showing only `planner_spec` catches the
  plan-fixture mutation.
- **F5** — native/once/twice-normalized values all inside `sanity_range`; `native_range` reachable
  on returned values.
- **Error contract (Q3), all four modes triggered:**

  | trigger | result | matches docs? |
  |---|---|---|
  | unknown descriptor id | `ConfigurationError: unknown descriptor: nope; valid descriptors: …` | yes (`errors.rb:23`) |
  | unknown algorithm | `ConfigurationError: sonance plan invalid: algorithms[0].name is not allowed` | yes — and `README.md:55-61` explicitly documents that the planner forwards unvalidated |
  | missing model file | `ConfigurationError: missing models directory: /tmp/nonexistent-models` | yes |
  | backend crash (`python3` → `/usr/bin/false`) | `BackendError: Essentia backend exited 1` | yes (`errors.rb:25`) |
  | missing / undecodable audio | `UnreadableAudioError` (a `TrackError`, re-raised by `analyze`) | yes (`README.md:38-45`) |

- **README API claims, executed verbatim** — all true: `verify!` → `true`; `analyze` → `Analysis`;
  `analyze_all` accepts mixed `String`/`Pathname` and preserves order; custom registry accepted.
- **Demand-driven planning** — `[:bpm_rhythm2013]` → `[]` required files (README's specific claim,
  confirmed); `[:embedding_musicnn]` → 1 file; `[:mood_happy_musicnn]` → 2; all nine → 6.
- **"compares all six descriptor values"** (`README.md:92`) — **accurate**. The golden fixtures have
  exactly 6 keys and `essentia_golden_spec.rb:20-28` lists exactly those 6. Not a finding. Worth
  knowing though: the real-Essentia golden gate covers 6 of 9 descriptors; `bpm_rhythm2013`,
  `beat_confidence_rhythm2013` and `embedding_musicnn` have no golden.
- **CHANGELOG migration table vs. registry** — derived both and compared as sets: exact match, 9/9,
  no extras either direction.
- **Version consistency** — `version.rb` `0.3.0`, gemspec reads it, CHANGELOG heading `0.3.0`.
- **No stale descriptor ids exist anywhere in the repo.** Independent sweep of all 89 tracked files
  (below). The only hits were false positives and legitimate non-descriptor tokens.
- **Baseline suite** — `194 examples, 0 failures` on the real repo.
- **CONTEXT claim 3 re-verified independently** — `git diff --stat 1f8ad78 origin/main` on the app
  is empty; reading the local checkout is reading main.

## BELIEVED BY READING (not executed)

- The Docker/x86_64 release-gate instructions (`README.md:97-119`). I have no x86_64 Docker host, so
  I did not run the golden gate. The commands are internally consistent with
  `essentia_golden_spec.rb:1-7` and `Dockerfile.essentia` exists.
- The `SONANCE_ALLOW_NON_CANONICAL` / canonical-environment claims (`README.md:90-95`) — read
  `spec/support/canonical_essentia_environment.rb`, did not exercise the non-canonical branch.
- The backend-authoring contract (`README.md:36-45`) is consistent with `extractor.rb:75-91`, but I
  did not write a third-party backend to test it.
- F3's claim that the prefix heuristic "almost never fires" in *practice* — I proved the blind spot
  exists and is reachable; I did not survey every existing `%i[]` in the repo to count how often the
  heuristic currently saves it.

---

## EVIDENCE

Scratch clone for all mutation experiments (**outside both repos**):
`…/114a28aa-a39b-4f12-b984-096f60d7375d/scratchpad/gemclone`
Sweep script: same directory, `sweep.rb`. Neither repo was modified.

### Ground state

```
$ git -C /Users/lukeolson/projects/gems/mood_probe rev-parse HEAD origin/main
d514137a09facf8c64519e189aed57c3abaf5635
d514137a09facf8c64519e189aed57c3abaf5635
```

### Descriptor ids derived from the registry (not transcribed)

```
$ ruby -Ilib -e 'require "sonance"; r=Sonance::Registry.default; ...'
DESCRIPTOR IDS (9):
  valence_emomusic
  arousal_emomusic
  danceability_musicnn
  mood_acoustic_musicnn
  mood_relaxed_musicnn
  mood_happy_musicnn
  embedding_musicnn
  bpm_rhythm2013
  beat_confidence_rhythm2013
MODEL IDS (6):
  msd_musicnn_1
  danceability_msd_musicnn_1
  mood_acoustic_msd_musicnn_1
  mood_relaxed_msd_musicnn_1
  mood_happy_msd_musicnn_1
  emomusic_msd_musicnn_2
```

### F1 — the broken command

```
$ ruby -Ilib exe/sonance --models-dir /tmp/nonexistent-models \
    --descriptors bpm_rhythm2013 analyze spec/fixtures/sonance/audio/sine_440.wav
{
  "bpm_rhythm2013": "#<Sonance::Scalar:0x000000011ff3f9d8>"
}
exit=0
```

Same input through the library API, plus the serialization probe:

```
bpm_rhythm2013 => 110.60472869873047 (Sonance::Scalar)
beat_confidence_rhythm2013 => 2.2199807167053223 (Sonance::Scalar)
--- what JSON.pretty_generate does to that same hash ---
{
  "bpm_rhythm2013": "#<Sonance::Scalar:0x0000000100ebecf8>",
  "beat_confidence_rhythm2013": "#<Sonance::Scalar:0x0000000100eb1d00>"
}
--- does Value respond to to_json/as_json/to_h? ---
  to_json: true      <- Object#to_json, produces the to_s string
  as_json: false
  to_h: false
```

### CLI argument branches (all correct)

```
$ ruby -Ilib exe/sonance descriptors            -> 9 ids, exit=0
$ ruby -Ilib exe/sonance                        -> "expected analyze, descriptors, or models" exit=1
$ ruby -Ilib exe/sonance frobnicate             -> "expected analyze, descriptors, or models" exit=1
$ ruby -Ilib exe/sonance analyze /tmp/x.wav     -> "analyze requires --descriptors IDS" exit=1
$ ruby -Ilib exe/sonance --descriptors bpm_rhythm2013 analyze
                                                -> "analyze requires FILE" exit=1
$ ruby -Ilib exe/sonance models                 -> "models requires verify or fetch" exit=1
$ ruby -Ilib exe/sonance --help                 -> banner, exit=0
```

### F3 — gate detection boundary (scratch clone)

Gate green at unmodified main:

```
$ bundle exec rspec spec/descriptor_id_integrity_spec.rb
repository descriptor ids
  keeps every descriptor-list id registered
1 example, 0 failures
```

With cases A (mixed), B (all-stale, neutral name), C (all-stale, "DESCRIPTORS" prefix) injected:

```
       unregistered descriptor ids:
       spec/zz_case_a_spec.rb:1 totally_bogus_id
       spec/zz_case_c_spec.rb:1 mood_happy
       spec/zz_case_c_spec.rb:1 danceability
1 example, 1 failure
```

Case B is absent from that list. With **only** case B present:

```
=== gate with ONLY case B (wholly-stale array in a SCANNED file) ===
1 example, 0 failures
```

Case B content: `LEGACY_SET = %i[mood_happy danceability musicnn_embedding].freeze`

### F4 — file coverage

```
covered count: 47
tracked files: 89
=== TRACKED BUT NOT SCANNED BY GATE (42) ===
  CHANGELOG.md
  Dockerfile.essentia
  README.md
  python/sonance_extract.py
  spec/fixtures/sonance/baseline_v0_1_0/*.json
  spec/fixtures/sonance/golden/*.json
  spec/fixtures/sonance/plans/*.json
  … (Gemfile, Rakefile, gemspec, .rubocop.yml, audio fixtures, support python)
```

Injections into unscanned files, gate result:

```
=== gate with stale ids in python/, plans JSON, README ===
1 example, 0 failures

=== confirm the injections are actually present ===
612:_LEGACY_IDS = ["mood_happy", "danceability", "musicnn_embedding"]
21:      "id": "bpm_STALE_ID",
Stale doc reference: `musicnn_embedding` and `mood_happy`.
```

Full suite on the injected clone — only the plan fixture is caught, and by `planner_spec`:

```
       -:emit => [{from: "a0", id: "bpm_STALE_ID", kind: "scalar", take: {output: "bpm"}}],
       +:emit => [{from: "a0", id: "bpm_rhythm2013", kind: "scalar", take: {output: "bpm"}}],
     # ./spec/planner_spec.rb:18
194 examples, 1 failure
rspec './spec/planner_spec.rb[1:2]' # Sonance::Planner matches the committed algorithm_only plan fixture
```

Python carries no descriptor ids of its own:

```
$ grep -n -o -E "[a-z][a-z0-9]*_(emomusic|musicnn|rhythm2013)" python/sonance_extract.py | sort -u
(no output)
```

### Repo-wide stale-id sweep (all 89 tracked files, producers/stems derived from the registry)

```
PRODUCER SUFFIXES: emomusic, musicnn, rhythm2013
QUANTITY STEMS: arousal, beat_confidence, bpm, danceability, embedding,
                mood_acoustic, mood_happy, mood_relaxed, valence

=== TOKENS THAT LOOK LIKE DESCRIPTOR IDS BUT ARE NOT REGISTERED ===
bbpm_rhythm2013   spec/registry_spec.rb:52
core_musicnn      lib/sonance/registry.rb:194, spec/registry_spec.rb:64
mood_acoustic     CHANGELOG.md:16, lib/sonance/registry.rb:128-131, baseline_v0_1_0/*.json, …
mood_happy        CHANGELOG.md:18, lib/sonance/registry.rb:158-161, baseline_v0_1_0/*.json, …
mood_relaxed      CHANGELOG.md:17, lib/sonance/registry.rb:143-146, baseline_v0_1_0/*.json, …
beat_confidence   CHANGELOG.md:21
tensorflow_predict_musicnn  lib/sonance/plan.rb:27, lib/sonance/registry.rb:105, spec/planner_spec.rb:96
```

Every one classified, none stale:
- `bbpm_rhythm2013` — my scanner swallowing the `\b` in the regex `/…\bbpm_rhythm2013\b/`. False positive.
- `core_musicnn` — the model `pack` name. `tensorflow_predict_musicnn` — a graph algorithm name.
- `mood_acoustic` / `mood_relaxed` / `mood_happy` — model **filenames** (`mood_happy-msd-musicnn-1.pb`)
  in `registry.rb`, app **column names** in `baseline_v0_1_0/*.json` (CONTEXT confirms this is
  correct and I did not flag it), and the **"Previous id"** column of the CHANGELOG migration table.
- `beat_confidence` — likewise the CHANGELOG "Previous id" column.

**Conclusion: zero stale descriptor ids in the repository.** What makes this meaningful is that the
gate protecting that state has proven blind spots (F3, F4) — the repo is currently clean, but not
because the gate is keeping it clean.

### F5 — normalization

```
=== native/sanity ranges per descriptor (from registry) ===
  valence_emomusic        native=1.0..9.0  sanity=-3.0..13.0  kind=nominal
  arousal_emomusic        native=1.0..9.0  sanity=-3.0..13.0  kind=nominal
  danceability_musicnn    native=0.0..1.0  sanity=0.0..1.0    kind=hard
  mood_acoustic_musicnn   native=0.0..1.0  sanity=0.0..1.0    kind=hard
  mood_relaxed_musicnn    native=0.0..1.0  sanity=0.0..1.0    kind=hard
  mood_happy_musicnn      native=0.0..1.0  sanity=0.0..1.0    kind=hard
  embedding_musicnn       native=nil       sanity=nil         kind=unbounded
  bpm_rhythm2013          native=nil       sanity=nil         kind=unbounded
  beat_confidence_rhythm2013 native=nil    sanity=nil         kind=unbounded

=== would a double-normalized emomusic value be caught by sanity_range? ===
  native            = 4.338823318481445    in sanity -3.0..13.0? true
  normalized once   = 0.41735291481018066  in sanity? true
  normalized twice  = -0.07283088564872742 in sanity? true

=== is native_range reachable on a RETURNED value? ===
  value=110.60472869873047 native_range=nil units=bpm range_kind=unbounded
```

Only occurrence of the contract in the whole repo:

```
$ grep -rn -i "normaliz|native range|native value|native Essentia" --include='*.rb' --include='*.md' --include='*.py' .
README.md:5:descriptor's native range, declared on its registry row; normalization is the
(all other hits are unrelated local variables named `normalized`)
```

### Error contract

```
=== 3a. unknown descriptor id ===
Registry#fetch(:nope)       Sonance::ConfigurationError: unknown descriptor: nope; valid descriptors: …
Extractor#plan_for unknown  Sonance::ConfigurationError: unknown descriptor: nope; valid descriptors: …

=== 3b. unknown ALGORITHM on a custom registry row ===
plan_for unknown algorithm  NO RAISE          <- documented behavior, README.md:55-61
analyze unknown algorithm   Sonance::ConfigurationError: sonance plan invalid: algorithms[0].name is not allowed: 'NotARealAlgorithm'

=== 3c. backend crash / bad python ===
nonexistent python   Sonance::ConfigurationError: unable to launch Python executable /nonexistent/python
python that exits 1  Sonance::BackendError: Essentia backend exited 1

=== 3d. unreadable / missing audio ===
missing file      Sonance::UnreadableAudioError: … Could not open file "/tmp/definitely_missing.wav"
undecodable m4a   Sonance::UnreadableAudioError: … Invalid data found when processing i
```

### README claims executed verbatim

```
verify! -> true
analyze -> Sonance::Analysis, keys=[:bpm_rhythm2013, :beat_confidence_rhythm2013]
analyze_all -> [["sine_440.wav", true], ["white_noise.wav", true]]
custom registry ids -> [:bpm_rhythm2013]
custom analyze -> 110.60472869873047

=== demand-driven planning ===
  [:bpm_rhythm2013]      -> []
  [:embedding_musicnn]   -> ["msd-musicnn-1.pb"]
  [:mood_happy_musicnn]  -> ["msd-musicnn-1.pb", "mood_happy-msd-musicnn-1.pb"]
  all nine               -> ["msd-musicnn-1.pb", "emomusic-msd-musicnn-2.pb",
                             "danceability-msd-musicnn-1.pb", "mood_acoustic-msd-musicnn-1.pb",
                             "mood_relaxed-msd-musicnn-1.pb", "mood_happy-msd-musicnn-1.pb"]
```

### CHANGELOG table vs. registry

```
CHANGELOG new-id column (9): arousal_emomusic, beat_confidence_rhythm2013, bpm_rhythm2013,
  danceability_musicnn, embedding_musicnn, mood_acoustic_musicnn, mood_happy_musicnn,
  mood_relaxed_musicnn, valence_emomusic
Registry ids         (9): (identical)
MATCH: true
in CHANGELOG not registry: []
in registry not CHANGELOG: []
```

### Baseline suite and final repo state

```
$ bundle exec rspec        # real repo, unmodified
194 examples, 0 failures

$ git -C /Users/lukeolson/projects/gems/mood_probe status --porcelain=v1 -b
## main...origin/main
                                    <- clean

$ git -C /Users/lukeolson/projects/vibe-doctor status --porcelain=v1 -b
## docs/essentia-gem-v2-design...origin/docs/essentia-gem-v2-design
?? docs/superpowers/specs/2026-08-10-essentia-gem-generalization-review/phase-a/whole-branch/
                                    <- pre-existing untracked dir, present at session start; not mine

$ git -C /Users/lukeolson/projects/vibe-doctor diff --stat 1f8ad78 origin/main
                                    <- empty; local tree == main, CONTEXT claim 3 confirmed
```

**Both repos are clean and on their original branches. All mutation experiments were confined to the
scratch clone outside both repos.**

---

## WHAT I WOULD ASK THE IMPLEMENTER FOR

1. **F1/F2 together.** Give `Sonance::Value` an explicit serialization (`to_h`/`as_json`) covering
   all four value kinds, have `exe/sonance` use it, and **replace the `recording_cli_analyze.rb`
   stub with a spec that runs the real `Analysis` through the CLI** and asserts on a numeric value.
   Fixing F1 without fixing F2 leaves the same trap armed for the next release.
2. **F3.** Drop the `ids.any? { known }` half of the guard, or invert the gate: enumerate ids and
   require every id in a descriptor-shaped list to be registered, rather than requiring a valid id
   as the entry condition.
3. **F4.** Extend the globs to `python/**/*.py`, `**/*.json`, and `*.md`. F4's mitigations mean this
   is defence in depth today, but README/CHANGELOG are genuinely unguarded.
4. **F5.** Put the native-range statement in the YARD `@return` for `Extractor#analyze` and in the
   `Scalar` class doc, where a consumer reads it at the call site.
5. **F6.** Add 0.1.0 / 0.2.0 CHANGELOG sections, since those tags are advertised as the
   compatibility path.

F7 needs no action.
