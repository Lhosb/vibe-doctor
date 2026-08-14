# ESSENTIA-GEM-V2 Phase A — Slice 1 — TEST REVIEW

**Reviewer:** Test & TDD Enforcer
**Diff range (app):** `a99c3973a40ebd075469a0d841cbcf09b4e4809c..9e28d3fd5f6442acaa1ee6452865f720d3ab6cfb`
**Diff range (gem):** `5360f8fd8609eae39edb5dfab8a07f6439a0b137..f0f8127d94300d08e383e6400be04b0ff4658dd9`
**Files read before reviewing:** design §E.1, §F.2, §F.3, §J.3, §J.4, §J.5; `principal-sequencing.md`; `implementer.md`.
**Read-only:** no file in either repo was modified. Both worktrees confirmed clean at review start.

---

## T1 — The count oracle. **Self-referential. It has a state where it passes vacuously. MUST-FIX.**

### Answer, plainly

**No. The new form does not retain the property the old one existed for, and it additionally acquires a
state in which it is green while running zero examples.** Both sides of the comparison are now produced
by the same selector over the same suite in the same image, so the two numbers are structurally
incapable of disagreeing about anything the suite itself doesn't already agree with.

### The mechanism

```
expected=$(rspec --tag essentia --dry-run --format json | …example_count)   # selector S over suite T
output=$(rspec --tag essentia --format documentation)                        # selector S over suite T
grep -qE "^${expected} examples, 0 failures$"
```

`--dry-run` performs example *collection* and skips only example *execution*. Collection is exactly what
determines `example_count`, and it is exactly what determines the run's `N examples` line. `expected` is
therefore a restatement of the run's own count, not an oracle over it. The only residual signal the grep
carries is `0 failures` — which `test "$status" -eq 0` already carries. **The count clause contributes
nothing.**

### Scenario 1 — a golden fixture is added with no corresponding example. Gate stays GREEN.

This is the precise drift the old form caught, and it was a genuinely independent oracle because
`DECODABLE_FIXTURES` is a **hardcoded literal**, not a glob:

```ruby
# spec/integration/essentia_extract_golden_spec.rb:21
DECODABLE_FIXTURES = %w[chirp clicks sine_440 white_noise].freeze
```

The examples come from that constant; the old `expected` came from `ls golden/*.json | wc -l`. Two
independent sources. Drop a fifth JSON into `golden/` and forget the constant → old `expected` = 6, run
= 5 → RED.

Under the new form both sides are 5 → GREEN. The fifth golden file is never compared to anything, in
this slice or any future one, and nothing goes red. **Proven below that the old form goes RED on exactly
this count mismatch (exit 1).**

### Scenario 2 — the selector stops matching. Gate stays GREEN. This is the vacuous-pass state.

If `:essentia` is ever renamed, moved, or typo'd — and note that **§J.3 item 12 rewrites that very
describe block's constants in the behaviour commit** — `--tag essentia` matches nothing. RSpec prints
`0 examples, 0 failures` and exits 0. `expected` is `0`. The grep pattern becomes
`^0 examples, 0 failures$`, which **matches**. Gate green, Essentia never ran, Docker image built for
nothing.

I ran the workflow's exact `bash -c` body against a tag that matches nothing. **It exits 0.** This is the
`Set[].subset?` failure class, in the app's only Essentia enforcement point.

The old form was immune to this: its `expected` came off the filesystem and was ≥ 1 by construction, so
a zero-example run could never satisfy the grep (**proven below: old body, zero-selection state, exit 1**).

### This also contradicts the design text

§F.3, verbatim:

> `ci.yml:121` computes `expected=$(($(ls …/golden/*.json | wc -l) + 1))` … **The count assertion is a
> good anti-silent-skip device and must be kept** — but adding examples to that file breaks the
> arithmetic, and any new spec file does not run at all. Widen to a `--tag` selector **and derive the
> expected count from something that does not move when fixtures are added.**

The implementer correctly widened the selector (T2 below: clean). But "something that does not move when
fixtures are added" was read as "the suite itself" — and the suite moves in perfect lockstep with the
thing being checked, which is the one source that cannot serve as an oracle. The anti-silent-skip device
was not kept; it was removed.

### The form that keeps BOTH properties

Drift-proof (no hardcoded total, new `:essentia` specs may be added freely) **and** cross-checked against
an independent oracle (the filesystem), **and** non-vacuous. Minimum viable version — replace the equality
with a floor plus an independent lower bound:

```bash
set -euo pipefail
fixtures=$(ls spec/fixtures/mood_probe/golden/*.json | wc -l)   # independent oracle: the filesystem
floor=$(( fixtures + 1 ))                                        # goldens + the undecodable-audio example

expected=$(bundle exec rspec --tag essentia --dry-run --format json \
  | ruby -rjson -e 'puts JSON.parse(STDIN.read).fetch("summary").fetch("example_count")')

# Non-vacuity + independent cross-check. Fails if a fixture gains no example, or an example is dropped.
test "$fixtures" -ge 1
test "$expected" -ge "$floor" || {
  echo "essentia selector matched ${expected} examples; ${fixtures} goldens require at least ${floor}" >&2
  exit 1
}

output=$(bundle exec rspec --tag essentia --format documentation); status=$?
printf "%s\n" "$output"
test "$status" -eq 0 && grep -qE "^${expected} examples, 0 failures$" <<< "$output"
```

Why `>=` and not `==`: `>=` is drift-proof **upward** — G1/G2/G3 and any future `:essentia` spec raise
`expected` freely without touching the arithmetic, which was the whole point of the change. It stays
strict **downward** — a golden with no example, a dropped example, or a dead selector all fall below the
floor and go red. Every state the old form caught is still caught, and the vacuous-zero state is caught
too, which the old form only caught by accident.

Stronger version if you want the fixture-to-example correspondence asserted by identity rather than by
count — assert that each `golden/<name>.json` basename appears in exactly one dry-run
`full_description`. That upgrades the check from "enough examples exist" to "*this* fixture has *an*
example", and survives someone adding a fixture and an unrelated `:essentia` spec in the same PR (a state
the `>=` floor would pass). I would take the `>=` floor as the merge bar and the identity form as a
follow-up.

---

## T2 — Selection change. **Clean. Nothing dropped. APPROVE.**

`--tag essentia` is an exact superset of the old file selection, verified id-for-id, not by count.

Only one tag site exists in the app, at the describe level of the same file the old form named:

```
spec/integration/essentia_extract_golden_spec.rb:15:RSpec.describe "Essentia extraction goldens", :essentia do
```

Old and new selections yield the **identical five example ids** (evidence below). Nothing is silently
dropped. Confirmed the `test` job is unaffected: bare `bundle exec rspec` still selects 275 examples with
**0** of them from the golden spec, so the exclusion filter still holds where it should.

**Side effect worth recording (NIT 6):** `--tag essentia` *neutralises*
`config.filter_run_excluding essentia: true` (`spec/spec_helper.rb:17`) — RSpec drops a key from the
exclusion filter when the same key is added to the inclusion filter. Verified empirically: with
`ESSENTIA_SPECS` **unset**, `rspec --tag essentia` selected and *executed* all five examples. So
`-e ESSENTIA_SPECS=1` on the `docker run` line is now dead weight for selection purposes. Harmless, but a
reader will believe it is load-bearing and it is not. Either drop it or comment why it is retained.

---

## T3 — Gem CI. **Runs and propagates failure correctly. One untested-environment risk.**

**Failure propagation: correct.** Both jobs are bare `run:` scalars (`bundle exec rspec`,
`bundle exec rubocop`) with no pipes, so there is no pipefail hazard, and GitHub Actions runs `run:`
under `bash -e` — a nonzero exit fails the step and the job. No hardcoded example count anywhere in the
file (grepped). Both commands verified green locally on the current gem HEAD, independently of the
implementer's run: **66 examples / 0 failures**, **29 files / no offenses**.

**SHOULD-FIX 3 — the workflow has never executed, and its environment is untested against the lockfile.**
The gem repo has had no CI ever (confirmed by §F.1 and the principal), so this file is unexercised. Three
facts that interact:

- `.github/workflows/ci.yml` pins `ruby-version: "3.2"`.
- `.tool-versions` says `ruby 4.0.1` — the version the gem is actually developed on.
- `Gemfile.lock` (tracked) has `BUNDLED WITH 4.0.3`, a `CHECKSUMS` section, and
  `PLATFORMS: arm64-darwin-25, ruby` — **no `x86_64-linux`**.

`ruby/setup-ruby` with `bundler-cache: true` installs the bundler named in `BUNDLED WITH`. Bundler 4.0.3
running under Ruby 3.2 on `x86_64-linux`, resolving a lockfile whose only concrete platform is
`arm64-darwin-25`, is a combination that has never been run. The generic `ruby` platform is present so it
*should* resolve by building from source, but "should" is the word this slice exists to eliminate. Two
cheap de-risks: add `x86_64-linux` to `PLATFORMS` (`bundle lock --add-platform x86_64-linux`), and either
matrix `[3.2, 4.0]` or move the pin to `.tool-versions` via `ruby-version: .tool-versions`. Pinning 3.2
does correctly test the `required_ruby_version >= 3.2` floor and matches `TargetRubyVersion: 3.2`, so I
am not asking you to drop 3.2 — I am asking that the version developers actually run also gets covered,
and that the first real execution of this workflow not be on the PR that matters.

**NIT 8 —** `bundle exec rspec` in the gem has no non-vacuity floor either. If `.rspec`'s
`--require spec_helper` or the default pattern ever broke, RSpec would print `0 examples, 0 failures` and
exit 0, green. Same class as MUST-FIX 1, vastly lower probability, and this is what every gem's CI looks
like. Noting it only because you asked for the class, not because I would block on it.

**NIT 7 —** no `concurrency:` block, so superseded pushes keep burning runners. The app's `ci.yml` has the
same gap, so this is consistent, not a regression.

---

## T4 — `command_runner_spec` flake. **Real, structural, and *this slice* is what makes it CI-visible.**

**The point that matters most for disposition:** this spec has been latent because the gem had no CI. The
`rspec` job added in **this** slice is what starts running it on a shared 2-core `ubuntu-latest` runner.
Slice 1 does not cause the flake, but it does convert it from a local annoyance into a CI failure source,
starting with the next PR.

Two independent timing assumptions, both of which will bite (`spec/backends/command_runner_spec.rb`):

**(a) The PID-file race — this is the one the implementer hit.** Line 17 sets `timeout: 0.2`. Within
those 200 ms the child must boot a full Ruby VM, `spawn` a *second* Ruby VM, and only then
`File.write(pid_file, child)` (line 12). Line 21 then does `Integer(File.read(pid_file))` with no
existence guard. Two Ruby VM boots inside 200 ms is comfortable on an M-series Mac and routinely is not
on a loaded runner; when the timeout fires first, the file does not exist and the example dies on
`Errno::ENOENT` — an *error in evidence collection*, not a failure of the behaviour under test. The
assertion is sound; its setup is racing its own timeout.

**(b) `expect(elapsed).to be < 1.5` (line 22).** A wall-clock bound with only 7.5× headroom over the
timeout, on a shared runner, where the measured interval *includes* both VM boots. This will produce a
second, differently-shaped flake once (a) is fixed.

Minor, lower priority: `process_gone?` (line 33) uses `Process.kill(0, pid)`, which succeeds on a
**zombie**. If the runner terminates the group but the child is not yet reaped, this returns `false`
after its 1 s deadline and the example fails despite correct behaviour.

**Recommended disposition — separate ticket, not this slice. The implementer was right not to touch it.**
Decouple the promptness proof from the boot cost rather than shaving margins: raise `timeout:` to ~2.0 s
and the two child `sleep`s to ~30 s, and raise the elapsed bound to ~10 s. Promptness is still genuinely
proven — the child would sleep 30 s, so returning in under 10 s can only mean the timeout fired and the
group was killed — while the assertion no longer depends on two VM boots finishing inside 200 ms. Then
guard line 21 (`expect(File).to exist(pid_file)` before reading) so that if it ever does race, the
failure message names the cause instead of surfacing as `ENOENT`. Optionally have `process_gone?` treat a
zombie as gone.

---

## T5 — Future-gate impact

1. **MUST-FIX 1 is the material one.** G1, G2 and G3 all land in the app behaviour slice and all run
   under this same job. Those three carry the entire "same six numbers" claim. If the count oracle cannot
   detect a spec that stops being *selected*, then a G1 that is mis-tagged, renamed, or excluded is
   invisible — the job goes green having asserted nothing. The gate that is supposed to protect the other
   gates is the one that is vacuous. Fixing it now is far cheaper than discovering it during slice 5.
2. **SHOULD-FIX 2 — the frozen bytes have no gate, only prose.** The slice's stated purpose is guardrails
   that survive a rollback, and the irreversible asset is the baseline bytes. The only thing defending
   them is `README.md` saying they must never be rewritten. There is no state in which that README fails.
   The principal named the concrete hazard explicitly: §J.3 item 11 rewrites `generate_goldens.rb`, and
   *"if that generator globs a directory pattern rather than the literal `golden/` path, it takes the
   baseline with it."*

   A pure-Ruby spec asserting each `baseline_v0_1_0/*.json` SHA-256 equals a committed constant would
   close this. It needs no Essentia, no Docker, no models, and — critically — **no v0.2.0 API**, so
   unlike the deferred G1 parity spec and the deferred F.2 mirror it is green today and stays green after
   a rollback to v0.1.0. It is rollback-surviving infrastructure by the slice's own definition. The
   implementer's evidence already contains the four hashes; they just are not asserted anywhere. I am
   ranking this SHOULD-FIX rather than MUST-FIX only because §E.1 asks for the header comment and does
   not itself ask for a gate — but it is the single highest-value thing missing from this slice.
3. **NIT 5 — no `set -euo pipefail` in the `docker run … bash -c` body.** Today a crashed dry-run leaves
   `expected` empty, the grep pattern becomes `^ examples, 0 failures$`, and the gate goes red — it fails
   safe, but by side effect rather than by design, and one refactor away from failing open. Add
   `set -euo pipefail` so a broken oracle is unambiguous. (Included in the T1 replacement above.)
4. NIT 6, `ESSENTIA_SPECS=1` now being inert for selection — see T2.

---

## Things I checked and found correct

- **Baseline placement.** `baseline_v0_1_0/` is a **sibling** of `golden/`, never nested, in both repos —
  §E.1's SF-1 interaction respected. Confirmed the fixture arithmetic in my proposed T1 fix is unaffected
  by it (`ls golden/*.json` = 4).
- **Byte identity.** Independently re-verified: all four baseline JSONs are byte-identical to their
  `golden/` sources in each repo, and the two repos' baseline directories are byte-identical to each
  other. §E.1's "freeze in BOTH repos (R1)" satisfied.
- **Retirement procedure present in-directory**, not only in the design doc — §E.1's R3 requirement. Using
  a `README.md` rather than a comment inside the JSON is the right call: it keeps the frozen files as
  unmodified, valid JSON, which is what the freeze is *for*.
- **Dependabot `ignore` for `mood_probe`** (§J.3 item 7) present and well-formed. The principal identified
  this as the mechanism that stops gem slices 2–3 leaking into the app; it lands first, as required.
- **No behaviour change.** The app diff touches only `.github/` and new fixture files. The gem diff touches
  only a new `.github/` and new fixture files. No `lib/`, no `app/`, no Python, no registry, no planner,
  no mapper. Slice discipline held.
- **App suite green on HEAD** — 0 failures, and I did not assert a count.
- **Deferrals** (G1 parity spec, F.2 app mirror, `essentia_offline`/`essentia_golden`, unpushed tag) are
  per instruction not filed as findings, and I confirmed none of them are silently half-present: there is
  no pending, conditional, or weakened stub anywhere in either diff.

---

## Findings, ranked

| Rank | # | Finding | Location |
|---|---|---|---|
| **MUST-FIX** | 1 | Count oracle is self-referential; passes vacuously on zero-selection and misses fixture-without-example drift. Contradicts §F.3's "must be kept". Replacement form supplied. | `vibe-doctor/.github/workflows/ci.yml:120-124` |
| SHOULD-FIX | 2 | Frozen baseline bytes have no gate — only a README with no failing state. Pure-Ruby SHA-256 spec closes it with no v0.2.0 dependency. | `spec/fixtures/mood_probe/baseline_v0_1_0/` (both repos) |
| SHOULD-FIX | 3 | Gem CI never executed; Ruby 3.2 pin vs `.tool-versions` 4.0.1, lockfile `BUNDLED WITH 4.0.3` + no `x86_64-linux` platform. | `mood_probe/.github/workflows/ci.yml:19-21`, `Gemfile.lock` |
| SHOULD-FIX | 4 | `command_runner_spec` flake — PID-file race against a 0.2 s timeout, plus a 1.5 s wall-clock bound. **Separate ticket.** This slice's new `rspec` job is what exposes it to CI. | `mood_probe/spec/backends/command_runner_spec.rb:17,21,22` |
| NIT | 5 | No `set -euo pipefail` in the `bash -c` body; empty-`expected` fails safe only by side effect. | `vibe-doctor/.github/workflows/ci.yml:120` |
| NIT | 6 | `-e ESSENTIA_SPECS=1` is now inert for selection — `--tag` neutralises the exclusion filter. Misleading to readers. | `vibe-doctor/.github/workflows/ci.yml:118` |
| NIT | 7 | Gem CI has no `concurrency:` block (app has the same gap). | `mood_probe/.github/workflows/ci.yml` |
| NIT | 8 | Gem `bundle exec rspec` has no non-vacuity floor. Same class as #1, far lower probability. | `mood_probe/.github/workflows/ci.yml:24` |

---

## Evidence

All commands run from the repos under review. Nothing modified.

### Diff scope

```
$ git -C /Users/lukeolson/projects/vibe-doctor diff --stat a99c3973..9e28d3fd
 .github/dependabot.yml                                    | 2 ++
 .github/workflows/ci.yml                                  | 7 ++++---
 spec/fixtures/mood_probe/baseline_v0_1_0/README.md        | 6 ++++++
 spec/fixtures/mood_probe/baseline_v0_1_0/chirp.json       | 8 ++++++++
 spec/fixtures/mood_probe/baseline_v0_1_0/clicks.json      | 8 ++++++++
 spec/fixtures/mood_probe/baseline_v0_1_0/sine_440.json    | 8 ++++++++
 spec/fixtures/mood_probe/baseline_v0_1_0/white_noise.json | 8 ++++++++
 7 files changed, 44 insertions(+), 3 deletions(-)

$ git -C /Users/lukeolson/projects/gems/mood_probe diff --stat 5360f8fd..f0f8127d
 .github/workflows/ci.yml                           | 39 ++++++++++++++++++++++
 spec/fixtures/mood_probe/baseline_v0_1_0/README.md |  6 ++++
 …/baseline_v0_1_0/{chirp,clicks,sine_440,white_noise}.json | 8 +++++ each
 6 files changed, 77 insertions(+)

$ git -C /Users/lukeolson/projects/vibe-doctor rev-parse HEAD
9e28d3fd5f6442acaa1ee6452865f720d3ab6cfb
$ git -C /Users/lukeolson/projects/gems/mood_probe rev-parse HEAD
f0f8127d94300d08e383e6400be04b0ff4658dd9
$ git -C … status --short        # both repos
(no output — both worktrees clean)
```

### T1 — THE DECISIVE RESULT. New gate body, selector matching nothing → **exit 0 (GREEN)**

Ran the workflow's exact `bash -c` body, substituting a tag that matches no example (simulating a rename,
a typo, or a filter change):

```
$ cd /Users/lukeolson/projects/vibe-doctor && bash -c 'expected=$(bundle exec rspec --tag essentia_golden --dry-run --format json | \
    ruby -rjson -e '\''puts JSON.parse(STDIN.read).fetch("summary").fetch("example_count")'\''); \
  output=$(bundle exec rspec --tag essentia_golden --format documentation); \
  status=$?; printf "%s\n" "$output"; \
  test "$status" -eq 0 && grep -qE "^${expected} examples, 0 failures$" <<< "$output"'; echo "GATE EXIT=$?"

Run options:
  include {essentia_golden: true}
  exclude {essentia: true}

Finished in 0.00045 seconds (files took 0.94735 seconds to load)
0 examples, 0 failures
GATE EXIT=0  (0 = PASSED / GREEN)
```

Zero examples executed. Gate green.

### T1 — the OLD gate body goes RED in both states the new one misses

Scenario 1, a golden fixture added with no matching example (`expected` = 6, run = 5):

```
$ ls spec/fixtures/mood_probe/golden/*.json | wc -l
       4
$ bash -c 'expected=6; output=$(bundle exec rspec spec/integration/essentia_extract_golden_spec.rb --format documentation); status=$?; printf "%s\n" "$output" | tail -3; test "$status" -eq 0 && grep -qE "^${expected} examples, 0 failures$" <<< "$output"'; echo "OLD GATE EXIT=$?"
OLD GATE EXIT=1 (nonzero = RED, correct)
```

Scenario 2, zero-selection state, old body verbatim:

```
$ bash -c 'expected=$(($(ls spec/fixtures/mood_probe/golden/*.json | wc -l) + 1)); output=$(bundle exec rspec spec/integration/essentia_extract_golden_spec.rb --format documentation); status=$?; printf "%s\n" "$output" | tail -3; test "$status" -eq 0 && grep -qE "^${expected} examples, 0 failures$" <<< "$output"'; echo "OLD GATE EXIT=$?"

Finished in 0.0001 seconds (files took 0.0734 seconds to load)
0 examples, 0 failures
OLD GATE EXIT=1
```

Old form: RED in both. New form: GREEN in both.

### T1 — `expected` and the run count are the same number by construction

```
$ ESSENTIA_SPECS=1 bundle exec rspec --tag essentia --dry-run --format json | ruby -rjson -e 'puts …example_count'
5
$ bundle exec rspec --tag essentia --format documentation | tail -3
Finished in 7.11 seconds (files took 0.94758 seconds to load)
5 examples, 0 failures
```

### T2 — old vs new selection, compared by example id (not by count)

```
$ ESSENTIA_SPECS=1 bundle exec rspec spec/integration/essentia_extract_golden_spec.rb --dry-run --format json | ruby -rjson -e '…ids.sort'
./spec/integration/essentia_extract_golden_spec.rb[1:1]
./spec/integration/essentia_extract_golden_spec.rb[1:2]
./spec/integration/essentia_extract_golden_spec.rb[1:3]
./spec/integration/essentia_extract_golden_spec.rb[1:4]
./spec/integration/essentia_extract_golden_spec.rb[1:5]

$ bundle exec rspec --tag essentia --dry-run --format json | ruby -rjson -e '…ids.sort'
./spec/integration/essentia_extract_golden_spec.rb[1:1]
./spec/integration/essentia_extract_golden_spec.rb[1:2]
./spec/integration/essentia_extract_golden_spec.rb[1:3]
./spec/integration/essentia_extract_golden_spec.rb[1:4]
./spec/integration/essentia_extract_golden_spec.rb[1:5]
```

Identical. Nothing dropped.

Only tag site in the app:

```
$ grep -rn ":essentia" --include="*.rb" spec/
spec/spec_helper.rb:17:  config.filter_run_excluding essentia: true unless ENV["ESSENTIA_SPECS"] == "1"
spec/integration/essentia_extract_golden_spec.rb:15:RSpec.describe "Essentia extraction goldens", :essentia do
```

The `test` job is unaffected — bare `rspec` still excludes them:

```
$ bundle exec rspec --dry-run --format json | ruby -rjson -e '…'
total=275 essentia_selected=0
```

`--tag` neutralises the exclusion filter (NIT 6) — with `ESSENTIA_SPECS` **unset**:

```
$ bundle exec rspec --tag essentia --dry-run --format json | ruby -rjson -e '…example_count'
5
$ bundle exec rspec --tag essentia --format documentation | tail -4
  rejects undecodable audio
Finished in 7.11 seconds (files took 0.94758 seconds to load)
5 examples, 0 failures
```

Selected *and executed* without the env var.

### T3 — gem suite and lint, re-run independently on gem HEAD `f0f8127`

```
$ cd /Users/lukeolson/projects/gems/mood_probe && bundle exec rspec | tail -4
Finished in 0.86069 seconds (files took 0.07836 seconds to load)
66 examples, 0 failures
Randomized with seed 33681

$ bundle exec rubocop | tail -3
Inspecting 29 files
.............................
29 files inspected, no offenses detected
```

Gate is zero failures; no count asserted.

Environment mismatch (SHOULD-FIX 3):

```
$ cat .tool-versions
ruby 4.0.1
python 3.11.6

$ sed -n '/^PLATFORMS/,/^DEPENDENCIES/p' Gemfile.lock
PLATFORMS
  arm64-darwin-25
  ruby

$ tail -2 Gemfile.lock
BUNDLED WITH
  4.0.3

$ grep -n "TargetRubyVersion" .rubocop.yml
4:  TargetRubyVersion: 3.2

$ grep -n "ruby-version" .github/workflows/ci.yml
20:          ruby-version: "3.2"
34:          ruby-version: "3.2"
```

`spec.required_ruby_version = ">= 3.2"` in `mood_probe.gemspec`. `rubocop` is in the `Gemfile`, so
`bundle exec rubocop` resolves. Neither job has a hardcoded count:

```
$ ! grep -Eq 'essentia|docker|example_count|examples,' .github/workflows/ci.yml; echo $?
0
```

### T4 — the flake, read in full

`spec/backends/command_runner_spec.rb`:

```ruby
11        child = spawn(#{RbConfig.ruby.inspect}, "-e", "sleep 3")
12        File.write(ARGV.fetch(0), child)
13        sleep 3
17      expect { runner.call([RbConfig.ruby, "-e", script, pid_file], timeout: 0.2) }
21      child_pid = Integer(File.read(pid_file))      # <-- no existence guard
22      expect(elapsed).to be < 1.5                   # <-- wall clock, 7.5x headroom
34      deadline = … + 1
36      Process.kill(0, pid)                          # <-- succeeds on a zombie
```

Two Ruby VM boots must complete inside the 200 ms timeout for line 21 to have a file to read. It passed on
this machine during the runs above; that is not evidence about a 2-core shared runner.

### Files inspected

- `vibe-doctor`: `.github/workflows/ci.yml` (full), `.github/dependabot.yml`,
  `spec/integration/essentia_extract_golden_spec.rb` (full), `spec/spec_helper.rb:17`,
  `spec/fixtures/mood_probe/baseline_v0_1_0/*`, `CLAUDE.md`,
  `docs/superpowers/specs/2026-08-10-essentia-gem-generalization-design.md` §E.1, §F.2, §F.3, §J.3, §J.4, §J.5
- `mood_probe`: `.github/workflows/ci.yml` (full), `spec/backends/command_runner_spec.rb` (full),
  `spec/spec_helper.rb`, `.rspec`, `.rubocop.yml`, `.tool-versions`, `Gemfile`, `Gemfile.lock`,
  `mood_probe.gemspec`, `spec/fixtures/mood_probe/baseline_v0_1_0/*`
- `/tmp/maestri-reviews/ESSENTIA-GEM-V2/phase-a/slice-1/principal-sequencing.md`, `implementer.md`

---

The slice shape is right and the irreversible half — the frozen bytes, in both repos, with the retirement
procedure in-directory — is correctly done. Finding 1 must land before merge: it is a four-line change to
one file, and shipping it as written means the app's only Essentia gate can be green having run nothing.

VERDICT: APPROVE-WITH-CHANGES
