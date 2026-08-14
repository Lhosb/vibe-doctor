# ESSENTIA-GEM-V2 Phase A — Slice 1 — TEST RE-REVIEW, ROUND 2

**Reviewer:** Test & TDD Enforcer
**Scope:** the fixes only. Reviewed `9e28d3f..52141f6` (app) and `f0f8127..ac8f24b` (gem) — the round-1→round-2 deltas — with round-1 findings re-proved against the new bodies.
**Read-only:** no file in either repo was modified. Both trees confirmed clean and at the review HEADs at start and end. All mutation experiments were run against scratch copies outside both repos, then deleted.

---

## Round-1 findings: disposition

| Round-1 finding | Status | What proves it |
|---|---|---|
| **MUST-FIX 1** — count oracle self-referential; vacuous pass on dead selector; misses fixture-without-example | **CLOSED** | Dead selector → `floor=5 expected=0`, **exit 1**. Orphan fixture → `floor=6 expected=5`, **exit 1**. Passing control → `floor=5 expected=5`, **exit 0**. Real output in Evidence. |
| **SHOULD-FIX 2** — frozen bytes had no gate, only a README | **CLOSED** | New `spec/baseline_v0_1_0_integrity_spec.rb` in both repos has a real failing state for **EDIT, DELETE and ADD** — I verified DELETE and ADD myself, which the implementer had not. Deterministic and hermetic. Runs in both suites (verified by running, not reading). |
| **SHOULD-FIX 3** — gem CI Ruby/platform | **CLOSED as far as static review can go** | `ruby-version: "3.2"` removed from both jobs; no `.ruby-version` file, so `ruby/setup-ruby` falls through to `.tool-versions` → **4.0.1**, matching development. `x86_64-linux` added to `Gemfile.lock` PLATFORMS. Per dispatch, I make no claim about GitHub execution. |
| **SHOULD-FIX 4** — `command_runner_spec` flake | Deferred per ruling — not filed. (It recurred once during the implementer's own round-2 runs, which is consistent with my round-1 assessment that this slice's new `rspec` job is what exposes it.) |
| **NIT 5** — no `set -euo pipefail` | **CLOSED** — present, and it is now load-bearing (see T4). |
| **NIT 6** — `ESSENTIA_SPECS=1` inert for selection | **Still open**, unchanged. NIT E below. |

**Manager pre-verified claims: all confirmed, none wrong.** Integrity spec globs `*.json` and asserts the file set; app `.rspec` requires only `spec_helper`; app has 62 spec files; gem workflow pins no `ruby-version`; PLATFORMS includes `x86_64-linux`; tag `v0.1.0` peels to `5360f8f` and `git ls-remote --tags origin v0.1.0` returns nothing (unpushed).

---

## T1 — Re-run of my own round-1 proof, then an attack on the new form

### Both round-1 failure states now go RED. **CLOSED.**

The new body computes an **independent** floor from the filesystem — `find spec/fixtures/mood_probe/golden -maxdepth 1 -type f -name "*.json" | wc -l`, plus one for the undecodable-audio example — and requires the discovered RSpec count to clear it. That is a genuine second source, exactly what was missing.

- **Dead selector** (tag renamed): `floor=5 expected=0` → **exit 1**. In round 1 this same state was **exit 0** with zero examples run.
- **Orphan golden fixture** (5th JSON, no matching example): `floor=6 expected=5` → **exit 1**. In round 1 this was **exit 0**.
- **Passing control** (unchanged tree): `floor=5 expected=5` → **exit 0**. The gate is not merely red-always.

I note the `find`-based count is also an improvement over `ls` in its own right: `-maxdepth 1 -type f` means a subdirectory or a stray symlink can't inflate the floor.

### Attacking the new form

**(a) `test -n "$spec_files"` is unreachable. NIT.** Under `set -o pipefail`, a zero-match `grep -rl … | sort` exits 1, so the *assignment* `spec_files=$(…)` fails and `set -e` terminates the script before `test -n` is ever evaluated. The line is harmless but it reads like the non-vacuity guard and is not the thing doing the work — `set -euo pipefail` is. Worth a comment saying so, or dropping the line.

**(b) The `-ge` inequality — what it does NOT catch that `-eq` would. SHOULD-FIX, and I proved it green.**

`-ge` proves *"enough examples exist"*, not *"this fixture has an example"*. Construct: add a 5th golden fixture with no matching example (floor → 6) **and**, in the same window, two unrelated `:essentia` examples (expected → 7). `7 -ge 6` → **GREEN**, with an orphan fixture that is never compared to anything. Demonstrated below with real output.

This is the residual hole I named in round 1 when I proposed `-ge` as the merge bar and the per-fixture identity check as the stronger form. It matters more now than it did then, because **the slack grows monotonically and never shrinks.** Today the margin is zero (`expected == floor == 5`), so the floor is maximally tight. Once G1, G2 and G3 land in the app slice — say ~10 further `:essentia` examples — `expected ≈ 15` against `floor = 5`, and you could delete every golden example and still clear the floor. The check silently stops tracking fixtures at the exact moment the fixtures start mattering.

**Recommended for the app slice, not as a blocker here:** replace the scalar floor with a per-fixture correspondence assertion — each `golden/<name>.json` basename must appear in at least one dry-run `full_description`. That upgrades "enough examples" to "*this* fixture has *an* example" and is immune to margin decay. The dry-run JSON already carries `full_description`, so it is a few lines in the same `ruby -rjson` call that is already there.

**(c) `set -euo pipefail` interaction with the command substitutions — correct, and load-bearing.** Verified: a spec file that fails to load makes `rspec --dry-run` exit **1** (dry-run still *loads* every file, it only skips execution), `pipefail` propagates that past the `ruby` filter, the assignment fails, and `set -e` takes the job red **before** the floor is even compared. Confirmed by running the body with a bogus file in the set: **exit 1, no output past the pipeline.** The `set +e` / `status=$?` / `set -e` window around the real run is correctly scoped — it captures RSpec's status without letting a nonzero one escape early, and `test "$status" -eq 0` is then asserted explicitly.

---

## T2 — The discovery mechanism is ungated code. Two real holes; both fail LOUD, not silent.

`spec_files=$(grep -rlE "(:essentia|essentia:[[:space:]]*true)" spec --include="*_spec.rb" | sort)`

**What it discovers today: exactly one file**, `spec/integration/essentia_extract_golden_spec.rb`. No over-inclusion. Two near-misses worth recording: `spec/spec_helper.rb:17` contains `filter_run_excluding essentia: true`, which **matches the pattern** and is excluded only by `--include="*_spec.rb"`; and the new integrity spec contains zero occurrences of `essentia`, so it is correctly not pulled into the no-database job.

**Hole 1 — any `grep` exit ≠ 1 disarms the rails_helper guard. SHOULD-FIX.**

`if grep -l "rails_helper" $spec_files; then … fi` treats **exit 2 (error)** identically to **exit 1 (no match)** — both are "false", both mean "proceed". `$spec_files` is unquoted for word splitting, so a spec filename containing whitespace splits into non-existent paths, grep exits 2, and the guard passes **with a `rails_helper` file in the load set**. Proven below: guard passes, exit 2, on a file that literally begins `require "rails_helper"`.

The general statement is broader than the whitespace case: the guard's *failing* state and its *error* state are conflated, so any grep error (unreadable file, argument-list overflow, a bad path) silently disarms it.

**Hole 2 — the guard is a one-level text grep; transitive requires evade it. SHOULD-FIX (same fix family).**

A tagged spec whose first line is `require "support/db"`, where `support/db.rb` requires `rails_helper`, is discovered, greps clean, and passes the guard while loading Rails at runtime. Proven below. This is the realistic trigger: §J.3 item 15 adds new specs, and Rails apps routinely route `rails_helper` through `spec/support/*`.

Confirmed the app is safe from this **today**: `spec/spec_helper.rb` does **not** auto-require `spec/support/**` (that line lives in `rails_helper.rb`), and none of the three current support files require `rails_helper`. So the manager's "nothing forces `rails_helper` globally" is correct.

**Honest severity, stated plainly: neither hole produces a false green.** If the guard is disarmed and a Rails spec is loaded without a database, RSpec fails at load, `--dry-run` exits 1, `pipefail` fires, and the job goes **red** — which is MF-1 recurring loudly, not passing silently. The guard is therefore a **better error message in front of a gate that already works**, not the gate itself. That is why I rank both holes SHOULD-FIX rather than MUST-FIX. But it should be *documented* as diagnostic, because as written a reader will trust it as the load-set gate and it is not one.

**Fix for both:** read the list into an array rather than relying on word splitting (`while IFS= read -r f; do …; done <<< "$spec_files"`, or `grep -rlZ … | xargs -0`), and branch on grep's exit explicitly — `0` = fail the job, `1` = proceed, anything else = error out rather than proceed.

---

## T3 — The integrity spec: EDIT, DELETE and ADD all have real failing states. **CLOSED.**

The implementer proved EDIT only. I verified all three by running the spec's exact logic against scratch copies of the baseline directory:

- **EDIT** (one byte flipped in `clicks.json`) → digest mismatch → fail.
- **DELETE** (`sine_440.json` removed) → **file-set assertion** fails first, with a clear message, before any `Digest::SHA256.file` can raise `ENOENT`. Good ordering — the failure names the cause.
- **ADD** (a 5th JSON dropped in) → file-set assertion fails.
- **Control** (unmodified) → passes.

`expect(actual_files).to eq(expected_sha256.keys.sort)` is what makes DELETE and ADD fail; without it the `each` over the hash would simply skip a missing file's absence from the *set*. That assertion is doing real work and is correctly placed first.

**Deterministic and hermetic:** pure `Pathname#glob` + `Digest::SHA256.file`. No network, no clock, no database, no ordering dependence, no shared state. Safe under the gem's `config.order = :random`. Verified it passes standalone in both repos, so it carries no load-order dependency on other specs.

The gem copy omits the `require "digest"` / `require "pathname"` that the app copy carries — I checked whether that was luck, and it is not: the gem's `spec/spec_helper.rb` explicitly requires both at the top, and `.rspec` auto-requires `spec_helper`. Correct and idiomatic for a gem. No finding.

Both repos' hashes match each other and `diff -rq` across the two baseline directories is still clean.

---

## T4 — Correctness consequences of grep + two RSpec invocations

**No correctness defect. One design point worth recording.**

- `spec_files` is computed **once** and passed to both invocations, so the two processes cannot disagree about the load set. That was the thing to check and it is right.
- The two processes are otherwise independent. Collection — not execution — determines both `example_count` and the `N examples` line, and collection is deterministic here (no conditional `it`, no seed-dependent group in the essentia spec), so `expected` and the real run agree. If a future spec makes collection non-deterministic, the `grep -qE` cross-check fails, i.e. red — the correct direction.
- **`--dry-run` still LOADS every file.** This is the point worth recording: the dry-run is *itself* the real load-set gate — it exits 1 on any load failure and `pipefail` propagates it. The grep-based `rails_helper` guard is therefore redundant with a check that already exists and is not evadable by text tricks. That reinforces T2's conclusion: keep the guard for the message, but don't treat it as the protection.
- **NIT D:** the dry-run's `errors_outside_of_examples_count` and `failure_count` are parsed out of the JSON and then ignored — only `example_count` is read. In the state I constructed, the JSON carried `"errors_outside_of_examples_count":2` and nothing looked at it. It is *mitigated* by RSpec's exit code plus `pipefail` (verified red), so this is belt-and-braces. Noting it because the implementer's own round-1 local evidence asserted `failure_count.zero?` and that assertion did not survive into the workflow.

---

## T5 — Do the app `test` job and the gem `rspec` job actually run the integrity spec? **Yes. Confirmed by running.**

Not by reading. App: dry-run over the whole suite selects it (`total=276  integrity_selected=1`), it runs standalone (1 example, 0 failures), and the full suite is green with zero failures. Gem: `total=67  integrity_selected=1`, runs standalone, full suite green with zero failures. No filter excludes it in either repo — it carries no tag, and neither `filter_run_excluding essentia: true` nor any path pattern touches it.

---

## Findings, ranked

| Rank | # | Finding | Location |
|---|---|---|---|
| SHOULD-FIX | A | `-ge` floor proves "enough examples exist", not "this fixture has an example". Orphan fixture + unrelated `:essentia` examples → **GREEN** (proven). Slack grows monotonically; after G1/G2/G3 land the floor stops tracking fixtures. **File against the app slice**, where the margin appears. | `vibe-doctor/.github/workflows/ci.yml:126` |
| SHOULD-FIX | B | `rails_helper` guard: unquoted `$spec_files` + `if grep` conflates exit 2 with exit 1, so any grep error disarms it (proven); and it is a one-level text grep, so a transitive `require` evades it (proven). Fails **loud**, not silent — it is a diagnostic, not the gate. Document as such, or harden. | `vibe-doctor/.github/workflows/ci.yml:120-123` |
| NIT | C | `test -n "$spec_files"` is unreachable — `set -o pipefail` + `set -e` already kill the script on a zero-match grep. Reads like the non-vacuity guard; isn't. | `ci.yml:119` |
| NIT | D | Dry-run's `errors_outside_of_examples_count` / `failure_count` ignored; mitigated by exit code + `pipefail`. | `ci.yml:126-127` |
| NIT | E | *(round 1, still open)* `-e ESSENTIA_SPECS=1` remains inert for selection — `--tag` neutralises the exclusion filter. | `ci.yml:117` |

Nothing blocking. None of the open items can produce a false green on the current tree; A can once the margin opens up, which is why it belongs to the app slice rather than to this one.

---

## Evidence

All commands run against the review HEADs. Both repos verified clean before and after; every mutation was performed on scratch copies outside both trees and deleted afterwards.

### Scope and integrity of the review

```
$ git -C /Users/lukeolson/projects/vibe-doctor rev-parse HEAD
52141f60a8134146e82aca933233c23cb8a353a9
$ git -C /Users/lukeolson/projects/gems/mood_probe rev-parse HEAD
ac8f24bee584156859fc04f5f1a5a3e99058a5e8
$ git -C … status --short      # both repos, before and after
(no output — clean)
```

### T1 — the new gate body, three states

Body run verbatim from `ci.yml`, varying only the tag and the golden directory.

```
=== T1a DEAD SELECTOR (tag renamed) ===
floor=5 expected=0
GATE EXIT=1

=== T1b PASSING CONTROL (unchanged tree) ===
floor=5 expected=5
PASSED THE FLOOR
GATE EXIT=0

=== T1c 5th golden fixture added, NO matching example ===
fixtures=       5 floor=6 expected=5
GATE EXIT=1

=== T1d SAME orphan fixture, PLUS 2 unrelated :essentia examples (the -ge slack) ===
fixtures=       5 floor=6 expected=7
FLOOR PASSED — GATE GREEN
GATE EXIT=0
```

T1a and T1c were **exit 0** in round 1 and are **exit 1** now — the two states I raised are closed. T1b is the passing control. T1d is finding A.

### T1(c) — `set -euo pipefail` takes a load failure red before the floor is compared

```
$ bash -c 'set -euo pipefail
  spec_files="spec/integration/essentia_extract_golden_spec.rb spec/nope_spec.rb"
  fixtures=$(find spec/fixtures/mood_probe/golden -maxdepth 1 -type f -name "*.json" | wc -l)
  floor=$((fixtures + 1))
  expected=$(bundle exec rspec $spec_files --tag essentia --dry-run --format json 2>/dev/null | \
    ruby -rjson -e "…example_count")
  echo "REACHED FLOOR CHECK: floor=$floor expected=$expected"
  …'
GATE EXIT=1
--- output:
(empty — never reached the echo)
```

RSpec's own exit codes on a load error, confirming why:

```
$ bundle exec rspec …/essentia_extract_golden_spec.rb spec/nope_spec.rb --tag essentia --dry-run --format json
rspec exit=1
example_count=0 errors_outside=1

$ bundle exec rspec …/essentia_extract_golden_spec.rb spec/nope_spec.rb --tag essentia --format documentation
rspec exit=1
0 examples, 0 failures, 1 error occurred outside of examples
```

Note the summary line also cannot match `^N examples, 0 failures$`. Three independent things take this state red.

### T2 — what the discovery grep finds today

```
$ grep -rlE "(:essentia|essentia:[[:space:]]*true)" spec --include="*_spec.rb" | sort
spec/integration/essentia_extract_golden_spec.rb
(exit=0)

$ grep -c "essentia" spec/baseline_v0_1_0_integrity_spec.rb
0

$ sf=$(grep -rlE … ); if grep -l "rails_helper" $sf; then echo "GUARD FIRES"; else echo "GUARD PASSES (exit=$?)"; fi
GUARD PASSES (exit=1)
```

### T2 hole 1 — whitespace filename disarms the guard (scratch tree, outside both repos)

A file named `weird name_spec.rb` whose **first line is `require "rails_helper"`** and which is tagged `:essentia`:

```
discovered:
spec/transitive_spec.rb
spec/weird name_spec.rb
grep: spec/weird: No such file or directory
grep: name_spec.rb: No such file or directory
>>> GUARD PASSES — rails_helper file slipped through (grep exit=2)
```

### T2 hole 2 — transitive require evades the guard (scratch tree)

```
discovered: spec/transitive_spec.rb
--- contents of the discovered spec:
require "support/db"
RSpec.describe "transitive", :essentia do
  it "y" do
  end
end
--- contents of what it requires:
require "rails_helper"
>>> GUARD PASSES (exit=1) — but rails_helper IS loaded at runtime via support/db
```

App is safe from this today — `spec/spec_helper.rb` does not auto-require `spec/support/**`, and none of `auth_helpers.rb`, `phase3_parity.rb`, `vibe_map_helpers.rb` requires `rails_helper`.

### T3 — integrity spec logic vs EDIT, DELETE, ADD (scratch copies of the baseline dir)

Same code as the committed spec, same pinned digests, pointed at a mutated copy:

```
=== CONTROL: unmodified copy ===
PASS
exit=0

=== DELETE: remove sine_440.json ===
FILE SET MISMATCH: ["chirp.json", "clicks.json", "white_noise.json"]
                != ["chirp.json", "clicks.json", "sine_440.json", "white_noise.json"] (RuntimeError)

=== ADD: restore, then add a 5th json ===
FILE SET MISMATCH: ["chirp.json", "clicks.json", "extra.json", "sine_440.json", "white_noise.json"]
                != ["chirp.json", "clicks.json", "sine_440.json", "white_noise.json"] (RuntimeError)

=== EDIT: restore, then flip one byte in clicks.json ===
(digest mismatch — raised from the each-loop at line 12)
```

Cross-repo byte identity still holds:

```
$ shasum -a 256 spec/fixtures/mood_probe/baseline_v0_1_0/*.json      # gem
b2a04b17…  chirp.json
50c7ee15…  clicks.json
1c4bfbc2…  sine_440.json
7a17251f…  white_noise.json
$ diff -rq <gem>/baseline_v0_1_0 <app>/baseline_v0_1_0
(no differences)
```

Both match the digests pinned in both spec files.

### T5 — the integrity spec actually runs in both jobs

```
=== APP: whole-suite dry run ===
total=276  integrity_selected=1
  ./spec/baseline_v0_1_0_integrity_spec.rb[1:1]  mood_probe v0.1.0 frozen baseline keeps every frozen JSON file byte-identical

=== APP: standalone ===
1 example, 0 failures

=== APP: full suite ===
276 examples, 0 failures

=== GEM: whole-suite dry run ===
total=67  integrity_selected=1
  ./spec/baseline_v0_1_0_integrity_spec.rb[1:1]

=== GEM: standalone ===
1 example, 0 failures

=== GEM: full suite ===
67 examples, 0 failures
```

Gate is zero failures; no example count asserted.

### Lint, both repos

```
$ (app)  bundle exec rubocop     → 201 files inspected, no offenses detected
$ (gem)  bundle exec rubocop     →  30 files inspected, no offenses detected
```

### MF-4 — gem Ruby and platform (read-only assessment; no GitHub execution claimed)

```
$ cat .tool-versions
ruby 4.0.1
python 3.11.6

$ ls -a | grep -c "^\.ruby-version$"
0

$ grep -n "ruby-version" .github/workflows/ci.yml
(no matches)

$ sed -n '/^PLATFORMS/,/^DEPENDENCIES/p' Gemfile.lock
PLATFORMS
  arm64-darwin-25
  ruby
  x86_64-linux
```

With no `ruby-version` input and no `.ruby-version` file, `ruby/setup-ruby` resolves from `.tool-versions` → 4.0.1, matching development and the app's own toolchain. Correct as written. Whether Actions can provision 4.0.1 and resolve the lockfile on `x86_64-linux` is unverifiable locally, per dispatch.

### SF-5 — retirement text

Both READMEs now carry the §E.1 block verbatim, including "the old directory **kept**", the commit-message rationale naming upstream version / old and new values / reviewer, and "**Never an edit to, or deletion of, `baseline_v0_1_0/`**". Checked against the design text; nothing lossy.

### Manager pre-verified claims — all confirmed

```
$ git -C <gem> for-each-ref refs/tags/v0.1.0 --format='%(refname:short) %(objecttype) %(objectname)'
v0.1.0 tag f5c163bdfa4256210afd889cb70de86f8248cc4c
$ git -C <gem> rev-parse v0.1.0^{}
5360f8fd8609eae39edb5dfab8a07f6439a0b137
$ git -C <gem> ls-remote --tags origin v0.1.0
(empty — unpushed)
$ git -C <app> ls-files 'spec/**/*_spec.rb' 'spec/*_spec.rb' | wc -l
      62
```

### Files inspected this round

- `vibe-doctor`: `.github/workflows/ci.yml` (essentia job, full new body), `spec/baseline_v0_1_0_integrity_spec.rb`, `spec/fixtures/mood_probe/baseline_v0_1_0/README.md`, `spec/spec_helper.rb`, `spec/rails_helper.rb`, `.rspec`, `spec/support/*.rb`
- `mood_probe`: `.github/workflows/ci.yml`, `spec/baseline_v0_1_0_integrity_spec.rb`, `spec/spec_helper.rb`, `.rspec`, `Gemfile.lock`, `.tool-versions`, `lib/mood_probe/{model_store,result,extractor,backends/essentia_python}.rb` (require chain)
- `implementer.md` (round 2)

---

Both round-1 findings I raised are closed with real failing states and a passing control, and the frozen-byte gate is stronger than the implementer proved — the file-set assertion gives it teeth against deletion and addition, not just edits. The two remaining items are refinements: A belongs to the app slice, where the floor's margin actually opens up; B is a diagnostic that reads like a gate and should be labelled or hardened. Neither blocks this slice.

VERDICT: APPROVE
