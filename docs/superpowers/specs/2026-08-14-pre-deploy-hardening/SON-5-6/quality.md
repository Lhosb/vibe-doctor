# Code Quality Review — sonance issues #5, #6 (Tier 2 final gate)

**VERDICT: APPROVE** (all findings non-blocking; one is a numeric discrepancy worth recording, not a defect)

Repo: `/Users/lukeolson/projects/gems/mood_probe`
BASE_SHA: `d514137a09facf8c64519e189aed57c3abaf5635`
HEAD_SHA: `1bc6552fd8a8983012f852887caa4d9856e60f31`
Branch: `fix/cli-output-and-bounded-subprocess-reads` (not pushed, no PR)
Commits: `364b028` (#5), `3f1f511` (#6), `1bc6552` (review fixes — comments/docs only)

Implementer, test, and spec reports read in full before starting. Not relitigating: mutation counts (Litmus re-ran 9 independently, all matched), Plumb's spec/scope sign-off, Value-layer-in-scope determination, BackendError/FatalError classification, path-count figures against the shipped constant.

---

## 1. RSpec idiom — new specs vs. siblings

Compared `spec/backends/command_runner_spec.rb` and `spec/backends/essentia_python_spec.rb` diffs against their own existing (unchanged) content, and `spec/cli_spec.rb` against its own prior style.

- `essentia_python_spec.rb`'s existing style is `let(:runner)`/`let(:backend)` with `instance_double`, plain `it "..."` descriptions, `allow(...).to receive(...)`. The two new examples (`elides the middle of an oversized stderr...`, `leaves a stderr within the message ceiling untouched`) use exactly this pattern — same `let`s, same `instance_double`-backed `runner`, same `rescue`-and-assert idiom already used a few lines above for the existing "crash" example. No new idiom introduced.
- `command_runner_spec.rb`'s new `describe "bounded stream reads"` block follows the file's existing pattern of a nested `describe` with its own `let`/`before` (matches the timeout-handling `describe` block already in the file, not shown in the diff but present unchanged above it). `stub_const` usage is idiomatic RSpec, not house-invented.
- `cli_spec.rb`'s new examples keep the file's existing shape: bare `it` blocks calling a shared `run_cli`/now `analyze_cli` helper, asserting via `JSON.parse(stdout)`. The new `analyze_cli` private-ish helper method mirrors the existing `run_cli` helper already at the bottom of the file (same definition style, same place).

No fifth variant, no invented house style. **Non-blocking / no finding here.**

---

## 2. `Value#as_json` / `#to_json` placement and shape

```ruby
def as_json(*_args)
  raise NotImplementedError, "#{self.class} must implement as_json"
end

def to_json(*)
  as_json.to_json(*)
end
```

- Base-class `NotImplementedError` for an abstract method is the standard Ruby idiom (not something this codebase had used before — grepped `lib/` for prior `NotImplementedError` and found none — but there was no existing convention to contradict, and this is unambiguously idiomatic Ruby for "subclasses must implement this or fail loudly"). A third-party `Value` subclass that forgets `as_json` gets a `NotImplementedError` naming its own class at the call site, not a silent `Object#to_json` inspect-string leak — which is precisely the failure mode issue #5 was filed against. That is the right trade (loud failure over silent re-inheritance of the bug).
- `to_json(*)` forwarding all arguments to `as_json.to_json(*)` is correct and idiomatic — it's what lets `JSON.pretty_generate` (which threads generator state through nested `to_json` calls) format nested arrays/objects correctly, exactly as documented in the comment.
- Each concrete subclass (`Scalar`, `Categorical`, `Vector`, `Series`) implements `as_json` right next to its own `initialize`, matching the existing file's per-class organization (each subclass already groups its own accessors/validations near its own `initialize`). Comments on each are one line, stating the *shape rationale* ("optional members are omitted rather than null so the payload matches the keyword set `AnalysisBuilder` splats back into `Categorical`") rather than restating the code. Good density.

**Non-blocking / no finding.**

---

## 3. `essentia_python.rb` bounded-read implementation

- The chunked-read loop (`bounded_reader`) is readable: `while (chunk = stream.read(STREAM_CHUNK_BYTES)); buffer << chunk; next if buffer.bytesize <= MAX_STREAM_BYTES; record_overflow.call(stream_name); break; end`. Four lines, single responsibility, comment directly above explains *why* it kills rather than keeps draining.
- `MAX_STREAM_BYTES` (and `STREAM_CHUNK_BYTES`) are documented exactly where a maintainer reading `CommandRunner` will find them — as a comment block immediately preceding the constant declaration inside the class that uses them, not in a README or a distant file. The comment is substantial (correctly, per the escalation in round 2: it now states the ceiling *can* bite, with measured per-stream, per-duration figures and both binding path counts) but stays scoped to derivation and consequence, not implementation detail already visible in the code below it.
- Stderr elision (`truncate_stderr`) is clear: guard clause returns the original text untouched if under the ceiling; otherwise computes `elided` count, slices head/tail with `.scrub` (guards against a byte-slice landing mid multi-byte UTF-8 sequence — a detail I did not have to reverse-engineer, it's the obvious reason `.scrub` is there), and interpolates an explicit marker naming the elided byte count. Matches the spec's assertions (`"[... sonance elided #{elided} bytes ...]"`) exactly.
- `kill_group`'s `PORTABILITY` comment is a genuinely good practice here: it names the specific mistake ("do not simplify this rescue to ESRCH alone") a future refactor might make, states which OS breaks and how, and cites that it was verified by mutation. This is exactly the kind of comment that prevents the "gate that cannot fail" pattern this repo has a documented history of (per M2 in the implementer's own report — self-caught).

**Non-blocking / no finding.**

---

## 4. YARD chunking guidance on `Extractor#analyze_all` — 13 lines

Counted: 13 lines from "The whole batch runs through..." through "...pays the backend's process and model-load startup again." (inclusive of the blank separator line before the worked example).

This is the right amount, not an essay:
- 5 lines: mechanism + why (shared subprocess, linear growth, which constant governs it).
- 3 lines: concrete binding numbers (750 paths / 40 paths) — load-bearing, not decorative; a maintainer sizing a chunk needs these.
- 1 blank line + 4 lines: the actionable worked example (`each_slice(25)`) plus the one-sentence rationale for why chunking is left to the caller rather than done internally.

Every line carries information a caller needs to act correctly; none restates what's obvious from the method signature. **Non-blocking / no finding.**

---

## 5. `recording_cli_analyze.rb` / `recording_cli_values.rb` split — is the hazard expressed clearly enough?

Read both files in full (not just the diff). Both carry an explicit, *symmetric* warning:

- `recording_cli_analyze.rb`: "This file is loaded via RUBYOPT into the CLI subprocess only. Do not require it from the main RSpec process: the class_eval below would clobber `Sonance::Extractor` suite-wide."
- `recording_cli_values.rb`: "kept separate from the stub itself so a spec can assert its coverage without loading `recording_cli_analyze.rb`. That file monkey-patches `Sonance::Extractor` for the CLI subprocess; requiring it inside the main RSpec process would clobber the extractor for every other spec."

Each file states the hazard from its own side (the stub file says "don't require me here"; the values file says "here's why I exist separately from that file"), so a maintainer encountering *either* file first gets the warning, not just one. The one place in `cli_spec.rb` that does need the payload table (`"covers every registered descriptor in the recording stub"`) requires `recording_cli_values.rb` directly and has its own comment restating why it doesn't require the stub file. Three independent places carry the same warning in slightly different words tied to their own vantage point — that redundancy is appropriate given the stated cost (a silent 9-failure order-dependent bug) of getting this wrong. I don't think a future contributor "helpfully recombining them" would do so without first deleting or ignoring three separate comments that all say not to.

**Non-blocking / no finding** — this is exactly the kind of guardrail that should exist and does.

---

## 6. Small public API surface / no premature abstraction

- Public API surface added: `Value#as_json`, `Value#to_json` (and their 4 concrete overrides). Nothing else — `exe/sonance` is byte-unchanged (confirmed: `git diff --stat d514137 1bc6552 -- exe/sonance` is empty).
- All new `CommandRunner` methods (`pump`, `start_readers`, `bounded_reader`, `raise_stream_limit!`, `kill_group`) and `truncate_stderr` are `private` (confirmed: both live after their class's `private` keyword — `essentia_python.rb:64` for the `CommandRunner` methods, `essentia_python.rb:233` for `truncate_stderr`).
- No new class, no new module, no new service-object-shaped abstraction. This is exactly what the escalation in round 2 also chose *not* to do — the implementer explicitly declined to implement internal chunking (a real design decision that would have added a new abstraction/behavior) and instead documented the caller-side pattern, correctly treating "chunk internally" as a separate, un-reviewed behavior change deserving its own issue. That restraint is the right call and matches this project's "no new abstraction without local need" convention.

**Non-blocking / no finding.**

---

## Verification (run once, numbers observed)

```
$ bundle exec rspec
208 examples, 0 failures
```
Matches expectation exactly.

```
$ bundle exec rubocop
50 files inspected, no offenses detected
```

**Discrepancy from the dispatch's expected "45 files, 0 offenses":** I observed **50 files**, not 45. Investigated rather than dismissed: the prior SON-17-19 review (this same repo, one branch back, base `d514137`) recorded rubocop at **49 files** just before this branch was cut. This branch adds exactly one new file, `spec/support/recording_cli_values.rb`. `49 + 1 = 50`, which is what I observe. This is very likely a stale/typo'd expectation in the dispatch (45 vs 49/50), not a defect in the branch — 0 offenses either way, and file count naturally grows by exactly the one new file this branch adds. Flagging per instructions ("report the numbers you observe") rather than silently reconciling to the expected figure.

No Brakeman run — correctly N/A (plain Ruby gem, not in vibe-doctor's Gemfile as a Rails app dependency the way brakeman scans; the implementer's own report notes this and I did not find a Brakeman config in this repo).

---

## No-conflict / forbidden-file compliance (independently verified)

```
$ git diff --stat d514137 1bc6552 -- Dockerfile.essentia constraints.txt \
    spec/support/canonical_essentia_environment.rb spec/canonical_essentia_environment_spec.rb NOTICE
(empty)
```
Zero overlap with the files owned by the unmerged `fix/pin-python-stack-and-notice-uris` branch, confirmed directly rather than taken on the implementer's word.

---

## Findings summary

| # | Area | Severity | Finding | Blocking? |
|---|------|----------|---------|-----------|
| 1 | RuboCop file count | Informational | Dispatch expected 45 files; observed 50. Explained by one new spec/support file added on top of the prior branch's 49 — consistent with SON-17-19's last-recorded count, not a defect. | No |

No other findings across idiom, API-surface, abstraction, or readability review. Everything reviewed in scope is idiomatically consistent with this codebase's existing style, appropriately commented (neither under- nor over-documented), and the two files most at risk of being "helpfully recombined" carry redundant, well-placed warnings against exactly that.

## VERDICT: APPROVE

This is a correct, twice-reviewed (Spec APPROVE, Test APPROVE), independently-mutation-verified (Litmus) change. My only finding is informational (a numeric expectation mismatch, resolved by investigation, not a code defect). Not holding this hostage to style — recommend proceeding per the standing note that a rebase onto the moved `origin/main` (now `5647a12`) is needed before merge, which is explicitly not this review's concern.
