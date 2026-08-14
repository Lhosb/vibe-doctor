# ESSENTIA-GEM-V2 Phase A — Slice 1 — TEST RE-REVIEW, ROUND 3

**Reviewer:** Test & TDD Enforcer · **Scope:** my own round-2 findings only.
**Reviewed:** `52141f6..a5f71fd` (app), `ac8f24b..6c56f29` (gem).
**Read-only:** no repo file modified. Both trees clean and at the review HEADs before and after; every mutation ran on scratch copies outside both repos and was deleted.

**Method note:** rather than retype the gate, I **extracted the `bash -c` body verbatim from `ci.yml`** (YAML-parsed, `'\''` unescaped) and ran that. Each scenario is a `sed` of that extracted file, and I show the diff proving only the golden path / an array injection changed. So every result below is the shipped body, not a paraphrase.

---

## My prior findings

| Finding | Status | Proof |
|---|---|---|
| **SHOULD-FIX A** — `-ge` floor proves "enough examples exist", not "this fixture has an example"; orphan fixture + slack proved **GREEN** in round 2 | **CLOSED** | Same state, new body: **exit 1**, `Golden fixtures without an Essentia example: newfixture`. Passing control just inside the bound (same slack, all fixtures bound): **exit 0**. |
| **NIT C** — `test -n "$spec_files"` unreachable | **CLOSED** | `bash -x` shows `test 0 -gt 0` as the last command executed → exit 1. Genuinely reached and firing. |
| **NIT D** — dry-run `failure_count` / `errors_outside_of_examples_count` ignored | **CLOSED** | Both fire with distinct messages, exit 1, when injected non-zero. |
| **SHOULD-FIX B** *(round 2; routed as A)* — unquoted `$spec_files`, `if grep` conflating exit 2 with exit 1 | **CLOSED** | Unreadable spec file → **exit 2** with `Failed to inspect Essentia spec candidate: …`. The error path is now distinct from no-match. |
| Round-2 NIT E — `ESSENTIA_SPECS` inert | Deferred to slice 5 by ruling — not filed. |

**Manager pre-verification: all confirmed, nothing wrong.** I independently reproduced the `$?` semantics you checked: in the `else` branch of `if grep …`, `$?` is **1** on no-match and **2** on error (real output below). Quoted array, `--` separator, word boundary, basename gate, both dry-run counts, boundary comment, `Dir.children`, README pin — all present. Suites match: app 276/0 + rubocop 201 clean, gem 67/0 + rubocop 30 clean.

---

## SHOULD-FIX A — the state I proved GREEN in round 2 now goes RED, with a passing control

Four runs of the extracted body. A and B use a scratch golden dir with a 5th file (`newfixture.json`, no matching example); B and C inject two extra `:essentia` examples to recreate the slack that defeated the floor in round 2.

| Scenario | Fixtures | Floor | Expected | Result |
|---|---|---|---|---|
| **Control** — unchanged tree | 4 | 5 | 5 | **exit 0** — 5 examples, 0 failures |
| **A** — orphan fixture, no slack | 5 | 6 | 5 | **exit 1** — names `newfixture` |
| **B** — orphan fixture **+ slack** *(round 2's green state)* | 5 | 6 | 7 | **exit 1** — names `newfixture` |
| **C** — **passing control just inside the bound**: same slack, all 4 fixtures bound | 4 | 5 | 7 | **exit 0** — 7 examples, 0 failures |

B is the decisive one: `7 -ge 6` still clears the floor, so the floor alone would pass it exactly as it did in round 2 — the **basename binding** is what takes it red, and it does so with a message naming the orphan. C is the control you asked for: the gate is not merely red whenever slack exists; it discriminates on the actual fixture-to-example binding. The unchanged-tree control sits at `expected == floor == 5`, i.e. exactly on the floor's edge, and passes.

The binding also fires **before** the floor, so the failure message names the fixture instead of reporting an arithmetic mismatch. That is a real diagnostic improvement over what I proposed.

---

## The `include?` substring match — one real false-negative mode. SHOULD-FIX.

You asked. Yes, and I reproduced it.

**False negative (gate misses an orphan — fail-open).** `descriptions.any? { |d| d.include?(fixture) }` is an unanchored substring test, so a fixture whose basename is a **substring of another fixture's basename** is declared covered by that other fixture's example. Concretely, against the real spec's real descriptions:

- Real description: `Essentia extraction goldens matches the sine_440 golden output`
- Add `sine_44.json` → `"…sine_440…".include?("sine_44")` → **true** → `sine_44` counted as covered though it has no example.

Run with `sine_44.json` present **and** slack to clear the floor: **GATE EXIT=0, GREEN.** Full output below. Without slack the floor still catches it, so this needs both conditions — but that is exactly the compound state finding A existed to close, and it is still reachable through this one crack.

Plausibility: the current names are `chirp`, `clicks`, `sine_440`, `white_noise`. A future `sine.json` or `chirp.json`-adjacent short name collides; a longer name (`clicks_44100.json`, the 44.1 kHz click train from §J.2/R2) does **not**, because the long name is not a substring of the short description. So the hazard is specifically *adding a shorter name that prefixes an existing one*.

**Fix — one line, and it mirrors the word-boundary fix already applied to the discovery grep in finding B:**

```ruby
missing = fixtures.reject { |fixture| descriptions.any? { |d| d.match?(/\b#{Regexp.escape(fixture)}\b/) } }
```

`\b` resolves this exact case: `sine_44` followed by `0` has no word boundary, so the false match disappears. Anchoring on the full phrasing (`"matches the #{fixture} golden output"`) would be tighter still but couples the gate to one description format.

**False positive (spurious red — fail-closed, acceptable, worth documenting).** A fixture genuinely covered by an example whose description does not contain the basename is flagged missing. That is the safe direction, but it imposes a real constraint on future authors: **every golden example's description must contain its fixture basename.** §J.3 item 12 rewrites this spec's constants in the behaviour commit, so whoever does that needs to know. One sentence in the existing boundary comment would cover it. I am flagging this as a NIT rather than folding it into your deferred "future G1 author needs to glob `*.json`" item, because it is a different constraint on a different author.

---

## Integrity spec, now with README pinned and `Dir.children` — still catches everything

Re-verified all three classes against the round-3 spec logic, plus two new ones the README pin and `Dir.children` unlock:

| Mutation | Result |
|---|---|
| Control (unmodified) | PASS |
| **EDIT** a JSON byte | digest mismatch → fail |
| **EDIT the README** *(newly covered)* | digest mismatch → fail |
| **DELETE** a JSON | file-set mismatch → fail |
| **DELETE the README** *(newly covered)* | file-set mismatch → fail |
| **ADD** a JSON | file-set mismatch → fail |
| **ADD a non-JSON file** *(newly covered — `Dir.children` sees it, the old `glob("*.json")` did not)* | file-set mismatch → fail |
| Restored | PASS |

The move from `baseline_dir.glob("*.json")` to `Dir.children` is a genuine strengthening: the round-2 version could not see a stray file or a subdirectory added to the frozen directory. The file-set assertion still fires **before** any `Digest::SHA256.file` call, so a deletion fails with a message naming the set rather than an `ENOENT` backtrace. Pinned README digest `a85485fc…` verified correct against both repos' actual files; both baseline directories are still byte-identical to each other.

**NIT:** `Dir.children` will also fail on a macOS `.DS_Store`. Correct strictness, but it means a Finder visit red-lights a developer's suite with a confusing set mismatch. Worth one line in the failure message or the README, not worth changing the assertion.

---

## Findings

| Rank | Finding | Location |
|---|---|---|
| SHOULD-FIX | `include?` is an unanchored substring test; a fixture basename that prefixes another is declared covered. Proven GREEN with `sine_44.json` + slack. One-line `\b` fix, symmetric with the discovery-grep fix already applied. | `vibe-doctor/.github/workflows/ci.yml:149` |
| NIT | The binding silently requires every golden example's description to contain its fixture basename. §J.3 item 12 rewrites this spec — document it in the existing boundary comment. | `ci.yml:145-150` |
| NIT | `Dir.children` fails on `.DS_Store`; correct but confusing locally. | `spec/baseline_v0_1_0_integrity_spec.rb:18` (both repos) |

Neither the SHOULD-FIX nor the NITs can produce a false green on the current tree — the substring hole needs a future fixture name that prefixes an existing one *plus* slack. This is strictly better than round 2, where the whole compound class was open.

---

## Evidence

### Repos untouched

```
$ git -C <app> rev-parse HEAD → a5f71fd2dc682518a06ce759bac3a7921169ec25
$ git -C <gem> rev-parse HEAD → 6c56f2915061487ce0cf95add1c529eb37ff47ab
$ git -C … status --short     → (no output, both, before and after)
```

### Gate body extracted verbatim from `ci.yml`, then run

```
$ ruby -ryaml -e '…extract steps["Run Essentia golden specs"].run, take the -c payload, unescape '\''…'
extracted 48 lines

=== PASSING CONTROL: the EXACT extracted body, unchanged tree ===
  rejects undecodable audio
Finished in 7.34 seconds (files took 0.08112 seconds to load)
5 examples, 0 failures
GATE EXIT=0
```

Scenario diffs prove only the golden path and the array injection differ:

```
$ diff gate_body.sh scenB.sh
13a14
> spec_files+=(".../extra_essentia_spec.rb")
27c28
<     fixtures=$(find spec/fixtures/mood_probe/golden -maxdepth 1 -type f -name "*.json" | wc -l)
---
>     fixtures=$(find .../golden5 -maxdepth 1 -type f -name "*.json" | wc -l)
36c37
<       fixtures = Dir["spec/fixtures/mood_probe/golden/*.json"]…
---
>       fixtures = Dir[".../golden5/*.json"]…
```

### SHOULD-FIX A — three scenarios

```
=== SCENARIO A (orphan fixture, no slack) ===
Golden fixtures without an Essentia example: newfixture
GATE EXIT=1

=== SCENARIO B (orphan fixture + slack — round 2's GREEN state) ===
Golden fixtures without an Essentia example: newfixture
GATE EXIT=1

=== SCENARIO C (PASSING CONTROL: same slack, all 4 fixtures bound) ===
7 examples, 0 failures
GATE EXIT=0
```

### `include?` false negative

```
=== real example descriptions ===
  Essentia extraction goldens matches the chirp golden output
  Essentia extraction goldens matches the clicks golden output
  Essentia extraction goldens matches the sine_440 golden output
  Essentia extraction goldens matches the white_noise golden output
  Essentia extraction goldens rejects undecodable audio

$ ruby -e 'd=["Essentia extraction goldens matches the sine_440 golden output"];
           puts "sine_44 considered covered: #{d.any? { |x| x.include?("sine_44") }}"'
sine_44 considered covered: true

=== orphan sine_44.json WITH slack ===
GATE EXIT=0
7 examples, 0 failures
```

### NIT C — the array-length check is reachable and fires

Discovery pattern swapped for one that matches nothing; `bash -x`:

```
+ test 1 -ne 1        # grep_status branch exercised with 1 (no-match), correctly continues
+ test 1 -ne 1
+ test 0 -gt 0        # <-- last command executed
GATE EXIT=1
```

### NIT D — both dry-run assertions fire

```
--- injected failure_count=2
GATE EXIT=1
Essentia dry run contained failures

--- injected errors_outside_of_examples_count=2
GATE EXIT=1
Essentia dry run contained load errors
```

### Round-2 finding B — grep error path is now distinct from no-match

`$?` semantics, verified independently of your check:

```
$ if grep -Eq "nomatchpattern" -- /tmp/probe_match.txt; then …; else gs=$?; echo "else \$?=$gs"; fi
  target=/tmp/probe_match.txt          else-branch $?=1
  target=/tmp/definitely_absent_file.txt else-branch $?=2
```

Unreadable spec file through the real body:

```
$ chmod 000 .../specdir/unreadable_spec.rb   # tagged :essentia
grep: .../unreadable_spec.rb: Permission denied
Failed to inspect Essentia spec candidate: .../unreadable_spec.rb
GATE EXIT=2
```

### Integrity spec

```
$ shasum -a 256 <app>/…/baseline_v0_1_0/README.md
a85485fc8c4277325d85282435002a6a099674c11acdfa5f109a0b3a76313a1a
$ shasum -a 256 <gem>/…/baseline_v0_1_0/README.md
a85485fc8c4277325d85282435002a6a099674c11acdfa5f109a0b3a76313a1a   (matches the pin in both specs)

$ ruby -e 'puts Dir.children("…/baseline_v0_1_0").sort.inspect'   # both repos
["README.md", "chirp.json", "clicks.json", "sine_440.json", "white_noise.json"]

=== CONTROL ===                          PASS
=== EDIT a json byte ===                 DIGEST MISMATCH
=== EDIT the README ===                  DIGEST MISMATCH
=== DELETE a json ===                    FILE SET MISMATCH: ["README.md","chirp.json","clicks.json","white_noise.json"]
=== DELETE the README ===                FILE SET MISMATCH: ["chirp.json","clicks.json","sine_440.json","white_noise.json"]
=== ADD a json ===                       FILE SET MISMATCH: [… "extra.json" …]
=== ADD a non-json file ===              FILE SET MISMATCH: [… "notes.txt" …]
=== RESTORED control ===                 PASS

$ diff -rq <gem>/…/baseline_v0_1_0 <app>/…/baseline_v0_1_0   → (identical)
```

### Suites and lint — gate is zero failures, no count asserted

```
$ (app) bundle exec rspec                                  → 276 examples, 0 failures
$ (app) dry-run selection check                            → total=276 integrity=1
$ (app) bundle exec rspec spec/baseline_v0_1_0_integrity_spec.rb → 1 example, 0 failures
$ (app) bundle exec rubocop                                → 201 files inspected, no offenses detected
$ (gem) bundle exec rspec                                  → 67 examples, 0 failures
$ (gem) dry-run selection check                            → total=67 integrity=1
$ (gem) bundle exec rspec spec/baseline_v0_1_0_integrity_spec.rb → 1 example, 0 failures
$ (gem) bundle exec rubocop                                → 30 files inspected, no offenses detected
```

Gem CI on GitHub: assessed by reading only, per dispatch. No claim made.

---

All four of my prior items are closed with real failing states **and** a passing control on each bound. The one new item is a narrow, fail-open crack in the binding I asked for, fixable in one line with the same `\b` idiom already applied elsewhere in this body.

VERDICT: APPROVE
