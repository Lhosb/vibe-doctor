# ESSENTIA-GEM-V2 Phase A — Slice 1 — TEST, ROUND 4 (final confirmation)

**Reviewer:** Test & TDD Enforcer · **Scope:** my round-3 findings + the extraction. Nothing else.
**Reviewed:** `a5f71fd..710620d` (app), `6c56f29..55d85fb` (gem). Trees clean, at review HEADs, before and after. No repo file modified; mutations ran on scratch copies outside both repos and were deleted.

---

## My prior findings

| Finding | Status | Proof |
|---|---|---|
| **SHOULD-FIX** — unanchored `include?`; `sine_44` bound to a `sine_440` description | **CLOSED** | `sine_44.json` + slack → **exit 1**, `Golden fixtures without an Essentia example: sine_44`. Passing control (same slack, no colliding fixture) → **exit 0**, 7 examples. |
| **NIT** — description-must-contain-basename constraint | Open by ruling (deferred item list) — not filed. |
| **NIT** — `Dir.children` trips on `.DS_Store` | **CLOSED** | Stray `.DS_Store` → PASS; every non-dot mutation class still fails. Table below. |

**Manager pre-verification: confirmed, nothing wrong.** `bin/essentia-ci` is mode 755, tracked in git as **100755**, shebang `#!/usr/bin/env bash`; my own `shellcheck bin/essentia-ci` exits **0**; the lint step precedes the docker build; the docker step invokes `/rails/bin/essentia-ci`. Suites: app 276/0 rubocop 201 clean, gem 67/0 rubocop 30 clean.

---

## The entrypoint discrepancy — **does not matter; do not redo the container run for it**

I proved the equivalence directly rather than reasoning about it. Both forms, same tree:

- shipped `bash bin/essentia-ci` → **exit 0**, 5 examples, 0 failures
- proven `./bin/essentia-ci` (shebang) → **exit 0**, 5 examples, 0 failures
- outputs byte-identical apart from RSpec's timing line

The only semantic difference is that `bash <file>` ignores the shebang and the executable bit, while direct exec requires both. The script has no `$0`/`BASH_SOURCE` logic, so nothing else can diverge. I also checked the thing that *could* have made the shipped form fail: `.dockerignore` has no `bin` rules and the Dockerfile does `COPY . .`, and the exec bit is tracked as `100755`, so the file reaches the image either way. **Shipped is a strict superset of proven in robustness** — it survives the exec bit being lost, which the proven form would not.

So the gap is real in principle and empty in substance. My recommendation: **do not re-run the amd64 build for this alone.** Fold the `--entrypoint bash … /rails/bin/essentia-ci` form into the next container run that happens for another reason, and record it then. Gating a fourth fix round on a difference I just proved is zero-width would cost more than it buys.

---

## The extraction — good execution, and it is **not yet testable**

Execution is sound: byte-for-byte the same logic, shellcheck clean and linted *before* the build so a defect fails fast without paying for a docker build, and the SC2068 re-introduction test you cite is a real falsifier for the lint step.

**But the durable payoff has not been collected yet.** `spec`, `spec/fixtures/mood_probe/golden`, and `bundle exec rspec` are hardcoded, so every scenario in this review still required a `sed`-ed copy of the script — precisely the fidelity gap the extraction was meant to eliminate. Three lines fix it:

```bash
SPEC_ROOT="${SPEC_ROOT:-spec}"
GOLDEN_DIR="${GOLDEN_DIR:-spec/fixtures/mood_probe/golden}"
RSPEC="${RSPEC:-bundle exec rspec}"
```

**Yes, it should have tests — this is my recommendation on record.** A plain RSpec spec in the app suite shelling out to the script against a fixture tree with a stub `rspec` on `PATH`. No Docker, no Essentia, runs in the existing `test` job. Highest-value cases, each mapping to a defect this team actually produced:

1. **Passing control** — unmodified inputs exit 0. Non-negotiable; a bound with no passing control proves nothing.
2. **Discovery traversal failure** → non-zero. *This round's MUST-FIX 1 and it currently has zero coverage — nothing proves the new `find`-to-tempfile guard fires.* Highest priority.
3. **Orphan fixture, with and without slack** → non-zero (round-2 SHOULD-FIX A).
4. **Prefix-collision fixture** (`sine_44` beside `sine_440`) → non-zero (round-3, mine).
5. **Discovery matches nothing** → non-zero (round-2 vacuity).
6. **Dead selector** → non-zero (round-1 MUST-FIX).
7. `rails_helper` guard fires; grep error path exits with grep's status.

Order I would do them: parameterise, then 1, 2, 3, 4. Items 3–6 are all regression tests for defects that shipped into review — they are the reason this slice took four rounds, and they are cheap once the script takes env overrides.

---

## Integrity specs after the dotfile change — no hole for anything git can see

| Mutation | Result |
|---|---|
| Control | PASS |
| EDIT a JSON byte | digest mismatch |
| EDIT the README | digest mismatch |
| DELETE a JSON | set mismatch |
| DELETE the README | set mismatch |
| ADD a JSON | set mismatch |
| ADD a stray non-JSON file | set mismatch |
| ADD a nested directory | set mismatch |
| Stray `.DS_Store` | **PASS** (intended fix works) |
| **Smuggled `.smuggled.json`** | **PASS** ← the hole |
| **Smuggled `.hidden/` directory** | **PASS** ← the hole |
| Restored | PASS |

You asked specifically about a dot-prefixed JSON smuggled in: **yes, it is invisible to the spec.** Assessment: the frozen bytes remain fully protected — all five pinned digests are still verified and every non-dot entry is still set-asserted — so nothing *existing* can be altered or removed undetected. What is lost is only "no untracked additions at all", and git backstops that: any dotfile other than `.DS_Store` still shows up in `git status`. `.DS_Store` is now gitignored in both repos, which is exactly the file the exemption was for.

**NIT:** the exemption is broader than the problem. `reject { |n| n == ".DS_Store" }` exempts the one file that caused the friction and closes the smuggling class entirely, for one character more specificity than `start_with?(".")`. Not worth a round; worth doing when the file is next touched.

---

## Findings

| Rank | Finding |
|---|---|
| SHOULD-FIX | `bin/essentia-ci` has no tests and is not yet parameterised to accept them. Discovery-failure guard (this round's MUST-FIX 1) has zero coverage. This is the extraction's payoff and it is uncollected. |
| NIT | Dotfile exemption is a whole class where one filename would do; a dot-prefixed file or directory can be added to the frozen dir unseen by the spec (git still sees it). |
| — | Entrypoint discrepancy: assessed, proven zero-width, no action beyond recording the shipped form on the next container run. |

Nothing blocking. Every prior finding of mine is closed with a falsifier and a passing control.

---

## Evidence

```
$ git -C <app> rev-parse HEAD → 710620db9cac66e8ce00811611131ad2dc6f22b0
$ git -C <gem> rev-parse HEAD → 55d85fb246e45581172d58066c24e41c8970ac9b
$ git -C … status --short     → (no output, both, before and after)

$ ls -l bin/essentia-ci
-rwxr-xr-x  1 lukeolson  staff  2470 bin/essentia-ci
$ head -1 bin/essentia-ci        → #!/usr/bin/env bash
$ git ls-files -s bin/essentia-ci → 100755 11a7f15… 0  bin/essentia-ci
$ shellcheck bin/essentia-ci     → shellcheck exit=0
$ grep -n "bin" .dockerignore    → (no bin rules);  Dockerfile: COPY . .
$ grep -rln "essentia-ci" spec/ .github/ → .github/workflows/ci.yml   (no spec covers it)
```

**Entrypoint equivalence**

```
--- shipped:  bash bin/essentia-ci
EXIT=0 … 5 examples, 0 failures
--- proven:   ./bin/essentia-ci
EXIT=0 … 5 examples, 0 failures
--- diff of the two outputs
14c14 < Finished in 6.7 seconds   > Finished in 6.78 seconds     (timing only)
```

**SHOULD-FIX closed.** Scenarios are `sed`s of `bin/essentia-ci`; diff confirms only the golden path and a slack injection differ.

```
=== A: sine_44.json alongside sine_440, WITH slack (my round-3 GREEN state) ===
EXIT=1
Golden fixtures without an Essentia example: sine_44

=== B: PASSING CONTROL — same slack, no prefix-colliding fixture ===
EXIT=0
7 examples, 0 failures
```

**Integrity specs** — mutation table above, produced by running the round-4 logic (`Dir.children(...).reject { |n| n.start_with?(".") }`) against scratch copies of the app baseline directory. Both repos' baseline directories still byte-identical (`diff -rq` clean).

**Suites — gate is zero failures, no count asserted**

```
$ (app) bundle exec rspec   → 276 examples, 0 failures
$ (app) bundle exec rubocop → 201 files inspected, no offenses detected
$ (gem) bundle exec rspec   → 67 examples, 0 failures
$ (gem) bundle exec rubocop → 30 files inspected, no offenses detected
$ (gem) bundle exec rspec spec/baseline_v0_1_0_integrity_spec.rb → 1 example, 0 failures
```

Gem CI on GitHub: assessed by reading only, per dispatch. No claim made.

VERDICT: APPROVE
