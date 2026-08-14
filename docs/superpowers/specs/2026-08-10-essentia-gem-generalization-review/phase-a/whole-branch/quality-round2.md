VERDICT: APPROVE

# 0.2.1 remediation re-review — Code Quality

Repo: `/Users/lukeolson/projects/gems/mood_probe`. Range: `848f6894a6022b5a32ae2b6b0c6898ac84986fa0..036c797f87e8a490dbcc676da0e7bfce8e0fb298`
(6 commits: `21de475`, `cfdd64f`, `3bc20b2`, `3ead830`, `63e1a01`, `036c797`).

## Ruling on my round-1 findings

### MUST-FIX 1 — CLI `analyze` broken — **CLOSED**, verified

`exe/mood-probe` now: requires `--descriptors` for `analyze` (aborts with a clear message before
constructing the extractor), passes `descriptors:` through to `Extractor#analyze`, and adds a
`descriptors` subcommand. The spec gap is also closed: `spec/cli_spec.rb` (new) shells the real
executable via `Open3.capture3` — genuine subprocess coverage, not a unit test.

I proved the spec would have caught the original bug: on a throwaway edit reverting `exe/mood-probe`
to the pre-fix body (`extractor.analyze(path)`, no descriptors, no guard), `spec/cli_spec.rb` failed
2/3 examples with the original `ArgumentError: missing keyword: :descriptors` surfaced verbatim in
`stderr` — exactly the defect I reproduced live in round 1. Restored the file immediately after;
`git status` was clean before and after.

### MUST-FIX 2 — README stale six-mood framing — **CLOSED**, verified

Opening paragraph now reads "extracts a registry of Essentia descriptors... native range... consumer's
responsibility... demand-driven planning... `[:bpm]` requires no model files" — this is an accurate
description of the actual registry/planner architecture, not a restatement of vibe-doctor's old
opinion. The code sample now uses `%i[bpm musicnn_embedding]`, not the old six. Two new sections
("Implementing a backend", "Adding an algorithm") were added; I checked the backend-contract claim
("returns a `TrackError` instance... does not raise it") against `lib/mood_probe/errors.rb`'s doc
comments and it matches exactly.

### SHOULD-FIX 3 — `extractor.rb:58` `is_a?(Backends::EssentiaPython)` — **CLOSED**

Changed to `backend.respond_to?(:analyze_all)`, per my round-1 recommendation. New coverage in
`spec/extractor_spec.rb` ("uses analyze_all on any backend that provides it") uses a real class
(not an RSpec double) whose `analyze` method raises if ever called — this genuinely proves the batch
method is selected and the serial method is never touched, for any conforming third-party backend,
not just the one concrete class. This is a stronger proof than a stubbed double could give.

I also re-tested the deeper concern from round 1 — that the G13 "stops the batch on SchemaError"
contract (`spec/extractor_v2_spec.rb`) is still only exercised through the serial branch, because its
plain `double("backend", analyze: nil, ...)` still does not `respond_to?(:analyze_all)`. That is true
and unchanged — the routing mechanism changed, but that suite still never drives a SchemaError through
`analyze_all`. However, I probed whether this still creates real drift risk by mutating
`result_for_values` to swallow `SchemaError` the same way it swallows `MalformedOutputError` (the exact
regression I hypothesized). On a scratch clone, the full suite still caught it — three failures, but for
a different, stronger reason than I expected: `Result.new(path:, error:)` itself raises
`ArgumentError: error must be a TrackError` when handed a `SchemaError`, because `Result` independently
enforces that only `TrackError` subclasses may be stored as a per-track error. That type invariant is
defense-in-depth I hadn't weighed in round 1: it makes the specific regression I was worried about
fail loudly regardless of which code path (`analyze` vs `analyze_all`) produced it. I no longer consider
this an open risk. (Residual NIT, not blocking: no spec drives a `SchemaError` through a real batch
subprocess end-to-end, but the type guard covers the gap a routing test would have covered.)

## Carried items (Test/Litmus unavailable)

### Item 7 — parity-spec 0.9e-4/1.1e-4 calibration controls — bite confirmed

On a scratch clone (`/tmp/mp_scratch`, deleted after use, never inside either working repo), I changed
the production tolerance in `spec/baseline_v0_1_0_parity_spec.rb` from `1e-4 * expected.abs` to
`2e-4 * expected.abs` and reran. Red, correctly attributed:

```
1) mood_probe v0.1.0 algebraic parity rejects a calibration perturbation just outside the parity bound
   expected RSpec::Expectations::ExpectationNotMetError with message matching
   /chirp\.json mood_happy drifted/ but nothing was raised
```

The "accepts... just inside" control still passed (as it should — it's inside both the old and the
loosened bound), so the pair correctly isolates which side of the boundary moved.

### Item 8 — `python_plan_fixture_spec.rb` non-vacuity floor — bite confirmed

On the same scratch clone, redirected fixture discovery to a nonexistent directory
(`fixtures/mood_probe/plans_nonexistent`). Result:

```
RuntimeError:
  no plan fixtures discovered
0 examples, 0 failures, 1 error occurred outside of examples
```

Genuine hard failure at load time, not a silent 0-example green pass. Scratch clone deleted after both
mutations (`rm -rf /tmp/mp_scratch`); confirmed no residue.

## Quality of the remediation diff itself (327 insertions / 21 files)

**Confirmed clean, no findings:**
- `registry.rb#fetch` and `plan.rb#graph_algorithm` both switch from bare `Hash#fetch(k)` to
  `fetch(k) { raise ConfigurationError, "..." }` — same idiom in both places, consistent with the
  project's existing explicit-failure convention. Both have real specs (`registry_spec.rb`,
  `planner_spec.rb`) asserting the new message text, not just the error class.
- Host-allowlist relocation (`model_store.rb`): `ModelStore.validate_download_uri!` is a single class
  method called from both `fetch_model!` (initial request) and `Downloader#request` (redirect
  follow-up) — one code path, not duplicated logic, so a redirect can't bypass the allowlist a second
  route would have missed. `model_store_spec.rb` proves the download is rejected *before*
  `downloader.download` is even called (`expect(downloader).not_to receive(:download)`).
- One real, minor regression in test *specificity* (not in behavior): the deleted
  `registry_spec.rb` example used to assert two host-confusion payloads directly —
  `https://essentia.upf.edu.evil.test/...` and `https://essentia.upf.edu@evil.test/...`. Those exact
  adversarial strings were not re-added at the new `model_store_spec.rb` location; only a plain
  non-matching host (`models.example.test`) is tested there now. I checked the new implementation
  (`uri.host == DOWNLOAD_HOST`, exact string equality) and it is not vulnerable to either payload — but
  the tests that used to prove that for this exact class of attack did not migrate with the code. NIT:
  worth re-adding those two payload cases to `model_store_spec.rb`'s allowlist test for symmetry with
  what was deleted, but this is not a live bug and I would not block on it.
- `spec/fixtures/mood_probe/golden/PROVENANCE.md` (item 6) correctly parallels the
  `baseline_v0_1_0/PROVENANCE.md` shape already reviewed in slice 3/4 — same voice, same
  regeneration-command structure, and honestly states the historical commit's generation method is
  unrecorded rather than inventing provenance.
- YARD additions (item 5) are accurate, not decorative: I spot-checked the `TrackError` family
  comments against README's new backend-contract section and `Extractor#analyze`/`#analyze_all`
  `@raise` tags against the actual `rescue`/`raise` sites in `extractor.rb` — they match the real
  control flow, including the correct distinction between raised (`FatalError`) and returned
  (`TrackError`) failures.
- `exe/mood-probe` stayed a flat `case`/`when` dispatch; the new `descriptors` subcommand is one line
  (`puts MoodProbe::Registry.default.ids`) and doesn't introduce new structure or state — it is not
  accreting without organization at this size (72 lines total).
- Version bump (item 10) touches only `version.rb`, `Gemfile.lock`, and `gemspec_spec.rb` — no stray
  edits.
- Confirmed myself, not just from the manager's baseline: `bundle exec rspec` → 184 examples, 0
  failures; `bundle exec rubocop` → 48 files inspected, no offenses; `git status --porcelain` clean;
  `v0.2.0` tag unmoved, still peels to `848f689`.

No regression found in the remediation diff itself.

## EVIDENCE

```
$ git -C /Users/lukeolson/projects/gems/mood_probe log --oneline 848f689..036c797
036c797 docs: clarify track error delivery
63e1a01 chore: bump version to 0.2.1
3ead830 test: harden public compatibility gates
3bc20b2 docs: describe generalized public API
cfdd64f fix: enforce public boundary contracts
21de475 fix(cli): require descriptor selection

$ git -C /Users/lukeolson/projects/gems/mood_probe diff 848f689..036c797 --stat
 21 files changed, 327 insertions(+), 31 deletions(-)

$ git -C /Users/lukeolson/projects/gems/mood_probe status --porcelain   # empty, before and after all edits
$ bundle exec rspec        # 184 examples, 0 failures
$ bundle exec rubocop      # 48 files inspected, no offenses
$ git tag -l -n1 v0.2.0 && git rev-list -n1 v0.2.0
v0.2.0  mood_probe v0.2.0 - Phase A release
848f6894a6022b5a32ae2b6b0c6898ac84986fa0   # unmoved

# MUST-FIX 1 regression proof (reverted exe/mood-probe to pre-fix body, then restored):
$ bundle exec rspec spec/cli_spec.rb
2 failures, stderr showed "ArgumentError: missing keyword: :descriptors" — matches original bug.
(restored file; rspec spec/cli_spec.rb green again, 3 examples 0 failures)

# Items 7/8 mutation testing, scratch clone outside both repos:
$ mkdir -p /tmp/mp_scratch && git clone -q .../mood_probe /tmp/mp_scratch/repo
$ git -C /tmp/mp_scratch/repo checkout -q 036c797
# item 7: tolerance 1e-4 -> 2e-4 => red, "chirp.json mood_happy drifted" expected but not raised
# item 8: fixture dir -> plans_nonexistent => RuntimeError "no plan fixtures discovered", 0 examples
$ rm -rf /tmp/mp_scratch   # deleted after use

# SHOULD-FIX 3 drift probe (also on the scratch clone, deleted with it):
# rescue MalformedOutputError -> rescue MalformedOutputError, SchemaError in result_for_values
$ bundle exec rspec
184 examples, 3 failures — Result.new raised ArgumentError: "error must be a TrackError"
(independent type invariant catches the regression regardless of routing path)
```

All commands run with `git -C`; no repository file was left modified. Only my own report file was
written.
