# ESSENTIA-GEM-V2 Phase A — Slice 1 SPEC RE-REVIEW, ROUND 2

**Reviewer:** Plumb (Spec Reviewer) · round-1 verdict was **REJECT** · **Tier:** 1 · read-only.

**Scoped to the fixes.** Round-1 → round-2 deltas:
- app `9e28d3f..52141f6` — 3 files, +47/−7
- gem `f0f8127..ac8f24b` — 4 files, +25/−3

Both amended into a single commit per repo (`52141f6 Add mood_probe rollback guardrails`,
`ac8f24b Freeze v0.1.0 golden baseline`). Both trees clean.

**VERDICT: APPROVE-WITH-CHANGES** — both MUST-FIXes I raised are genuinely closed, proven against the
exact failure modes I demonstrated in round 1. Three SHOULD-FIXes remain. None of them makes this
slice red now or after a rollback, so the slice's defining property holds; one of them is a latent
CI-red trap for slice 5 that costs one character to remove and should not be carried forward silently.

---

## Round-1 findings: disposition

| Round-1 finding | Now | Proof |
| --- | --- | --- |
| **MUST-FIX 1** — essentia job loads all 61 specs, dies with no DB | **CLOSED** | Same job body, no DB reachable: `errors_outside_of_examples_count=0`, `expected=5`, exit 0. Round 1 was 60 load errors / 0 examples. |
| **MUST-FIX 2** — vacuous count oracle (0 examples ⇒ green) | **CLOSED** for the failure mode that mattered | Dead tag: `floor=5 expected=0` → exit 1. Tag text gone entirely → grep empty → `set -e`/`pipefail` aborts. Residual: SHOULD-FIX 1. |
| **SHOULD-FIX 3** — lossy README | **CLOSED** | `diff` of design `:541-544` against README `:6-9` → **IDENTICAL** in both repos. |
| **SHOULD-FIX 4** — baseline immutable by convention only | **CLOSED** for the bytes | Integrity spec catches edit, JSON deletion, stray-JSON addition; runs in both suites. Residual: SHOULD-FIX 2. |
| **NIT 5** — gem CI pinned Ruby 3.2 | **CLOSED** | `ruby-version: "3.2"` removed from both jobs; `x86_64-linux` added to `PLATFORMS`. |
| **NIT 6** — `README.md` among the JSONs, G1 must glob `*.json` | carried forward | Still advisory for G1's author; the new integrity spec models the correct idiom. |
| **NIT 7** — gate boots RSpec twice | **withdrawn** | The load set is now one Rails-free file; the cost is negligible. |

---

## Answers

### R1 — Is MUST-FIX 1 genuinely closed, and is the grep discovery mechanism correct as a specification?

**The failure is closed. The mechanism is not equivalent to what RSpec selects — in both directions.**

**Closed.** The root cause was that `--tag essentia` with no file argument made RSpec fall back to
`spec/**/*_spec.rb`, loading 60 `rails_helper` files into a job with no postgres. The new body passes
an explicit, discovered file list. Run against the real app tree with the database unreachable — the
exact condition that produced 60 load errors in round 1:

```
$ DATABASE_URL="postgres://nobody:nobody@127.0.0.1:59999/nonexistent_db" ESSENTIA_SPECS=1 \
  RAILS_ENV=test bash -c '<the job body verbatim>'
errors_outside=0
floor=5 expected=5
DISCOVERY+FLOOR OK WITH NO DATABASE
EXIT=0
```

Discovery returns exactly the one Rails-free file, and the guard correctly finds no `rails_helper`:

```
$ grep -rlE "(:essentia|essentia:[[:space:]]*true)" spec --include="*_spec.rb" | sort
spec/integration/essentia_extract_golden_spec.rb
$ grep -l "rails_helper" spec/integration/essentia_extract_golden_spec.rb; echo $?
1
```

I did **not** rebuild the amd64 image; the Essentia half rests on the implementer's reported run
(5 examples, 0 failures, no PostgreSQL) and your pre-verification. What I independently proved is the
part that was broken: Rails is no longer loaded, so the absence of a database no longer matters.
`set -euo pipefail` behaves correctly here — `grep` returning 1 inside the `if` condition does not
abort (confirmed above), and a `grep`/`sort` pipeline finding nothing does abort via `pipefail`.

#### SHOULD-FIX 1 — `grep -rlE` for the literal tag text is not what RSpec selects; the floor cannot catch the under-inclusion half

**(a) Under-inclusion — and this one is invisible, not red.** RSpec metadata can be applied by means
other than literal text in a `*_spec.rb`. The commonest is `config.define_derived_metadata`.
Demonstrated with real RSpec in a scratch harness (4 golden JSONs, so `floor` = 5, identical to the
app):

```
spec/spec_helper.rb:
  config.define_derived_metadata(file_path: %r{spec/integration/essentia}) { |m| m[:essentia] = true }

$ grep -rlE "(:essentia|essentia:[[:space:]]*true)" spec --include="*_spec.rb" | sort
spec/integration/essentia_extract_golden_spec.rb          # 1 file

$ rspec --tag essentia --dry-run --format json   # what RSpec ACTUALLY selects
example_count=6
./spec/integration/essentia_empty_models_spec.rb          # 2 files
./spec/integration/essentia_extract_golden_spec.rb

$ <the exact job body, verbatim>
floor=5 expected=5
5 examples, 0 failures
FULL_JOB_BODY_EXIT=0     # GREEN, with the second spec never run
```

The floor cannot help: it is satisfied by the golden spec alone. Same blind spot for a tag carried on
a shared example group or shared context in `spec/support/**` — excluded by `--include="*_spec.rb"`.

This is the round-1 hazard relocated, not reintroduced: in round 1 the *entire* gate could vanish
silently; now only *additions* can. That is a large improvement and why MF-2 is closed. But the
concretely relevant addition is the **deferred F.2 app-side mirror**, which is exactly "a new
`:essentia`-tagged app spec."

**(b) Over-inclusion — this one goes red, with a misleading message.** `:essentia` has no word
boundary, so it matches `:essentia_offline`, `:essentia_golden`, and the near-certain one:

```
$ printf 'let(:essentia_mapper) { described_class.new }\n' > probe_spec.rb
$ grep -lE "(:essentia|essentia:[[:space:]]*true)" probe_spec.rb
probe_spec.rb            # MATCHED
```

J.3 item **1** creates `app/models/mood_vectors/essentia_mapper.rb`; item **15** adds its specs, which
must `require "rails_helper"` to autoload an `app/models` class. A single `let(:essentia_mapper)` or
`subject(:essentia_mapper)` in that file kills the essentia job:

```
$ <the exact job body, verbatim, on a harness with an untagged rails_helper mapper spec>
DISCOVERED:
  spec/integration/essentia_extract_golden_spec.rb
  spec/models/essentia_mapper_spec.rb
spec/models/essentia_mapper_spec.rb
Essentia specs must remain Rails-free in this no-database job
JOB_BODY_EXIT=1
```

The message names a file that is not an Essentia spec and was never tagged. **Today's tree is safe** —
verified: the only `essentia` mentions in the other app specs are the strings `"essentia_itunes"` /
`"essentia_youtube"` (6 files, 11 lines), none of which match the pattern.

Reviewer's note, not a prescription: a word boundary (`:essentia\b`) removes (b) for one character.
For (a) the structurally correct fix is to invert the mechanism — let RSpec do the selecting and
assert the *resulting* file set is Rails-free — which is equivalent to RSpec by construction; but that
needs the suite to load, which needs a database, which is what the implementer was avoiding. So the
honest minimum is: add the boundary, add a comment, and record the residual against slice 5.

---

### R2 — Is the count oracle closed? Is `+1` still right, and is the floor still independent?

**Closed. `+1` is still correct. The floor is genuinely independent of the selector. It catches total
collapse, by design not partial under-inclusion.**

**Independence.** `fixtures=$(find spec/fixtures/mood_probe/golden -maxdepth 1 -type f -name "*.json"
| wc -l)` is filesystem-derived and shares no code path with either the grep discovery or RSpec's tag
filter. It is a true external oracle, which is what round 1 lacked. `-maxdepth 1 -type f` is right —
it will not absorb a future `baseline_<version>/` sibling (it is not under `golden/`) nor any
subdirectory.

**`+1` is still the right constant.** It encodes the one tagged example not derived from a fixture
file — `it "rejects undecodable audio"` in `essentia_extract_golden_spec.rb:78`. Verified today:
`find … | wc -l` → 4, `floor` → 5, `expected` → 5 (4 `DECODABLE_FIXTURES` examples + 1). Because the
assertion is `-ge`, `+1` stays valid as tagged examples are added; it only needs revisiting if the
undecodable example were removed, which would then correctly show up as `expected 4 < floor 5`.

**Controls — both directions.** Dead selector (tag renamed so grep still matches but RSpec selects
nothing):

```
$ # spec tagged :essentia_offline; grep discovers it, --tag essentia selects nothing
floor=5 expected=0
DEAD_TAG_EXIT=1        # floor caught it
```

Tag text removed entirely (grep finds nothing at all):

```
NO_TAG_AT_ALL_EXIT=1   # pipefail + set -e abort before the floor is even reached
```

Passing control, same harness, tag intact: `floor=5 expected=5`, exit 0. So the gate has a state in
which it fails *and* a state in which it passes, just inside the bound.

**The honest limit**, stated because you asked directly: the floor is a lower bound, so if the
discovery under-includes while the golden spec is still found, `expected` stays ≥ 5 and the floor
passes. Demonstrated in R1(a). `expected` itself is still derived from the same selector as the real
run, so the `grep -qE "^${expected} examples, 0 failures$"` line remains a *consistency* check
(it catches runtime pendings/skips), not an oracle — the floor now does the oracle work. That
division is correct; I am not asking for it to change.

---

### R3 — Is the README verbatim against E.1, in both repos?

**Yes. Byte-identical, both repos, including the deletion prohibition and the full commit-message
rationale.** Mechanically diffed rather than eyeballed:

```
$ sed -n '541,544p' docs/.../2026-08-10-essentia-gem-generalization-design.md > e1.txt
$ sed -n '6,9p' <app>/spec/fixtures/mood_probe/baseline_v0_1_0/README.md > app_readme.txt
$ sed -n '6,9p' <gem>/spec/fixtures/mood_probe/baseline_v0_1_0/README.md > gem_readme.txt
$ diff e1.txt app_readme.txt   → IDENTICAL
$ diff e1.txt gem_readme.txt   → IDENTICAL
$ cmp <app>/…/README.md <gem>/…/README.md   → identical
```

The text now present in both:

```
> Retirement is a **new dated baseline directory** (`baseline_<version>/`), the old directory
> **kept**, and the rationale recorded in the commit message — naming the upstream model version, the
> old and new values, and who reviewed the delta. **Never an edit to, or deletion of,
> `baseline_v0_1_0/`.**
```

Checked against my round-1 table item by item: deletion prohibition ✅ ("or deletion of"), old
directory kept ✅ (explicit "**kept**"), commit-message rationale ✅ with all four elements — upstream
model version, old values, new values, who reviewed the delta. The `baseline_<version>/` naming
convention is now the design's own, replacing the paraphrase "dated sibling directory". **The gem
copy — the one that matters, since `grep` finds no other reference to `baseline_v0_1_0` anywhere in
that repo and the design doc does not exist there — is byte-identical to the app's.** SF-3 **CLOSED**,
nothing lost.

---

### R4 — Does the integrity spec deliver mechanical immutability?

**For the four JSON files, yes: edit, deletion and stray-JSON addition are all caught, in both repos,
and it survives the rollback. It does not cover the retirement instruction itself.**

Tested by copying the real baseline directory to scratch and running the repo's spec verbatim with
only the `let(:baseline_dir)` line redirected via `sed` (no repo file touched):

| Scenario | Result |
| --- | --- |
| unmodified | `1 example, 0 failures` ✅ passing control |
| one-byte append to `clicks.json` (**EDIT**) | `1 example, 1 failure` ✅ |
| `sine_440.json` removed (**DELETION**) | `1 example, 1 failure` ✅ |
| copy of `chirp.json` added as `stray.json` (**ADDITION**) | `1 example, 1 failure` ✅ |
| `README.md` **deleted** | `1 example, 0 failures` ❌ |
| `README.md` overwritten with `tampered` | `1 example, 0 failures` ❌ |
| `stray.txt` added | `1 example, 0 failures` ❌ |
| `nested/x.json` added | `1 example, 0 failures` ❌ (`glob` is not recursive) |

**Runs in both places.** App: `spec/baseline_v0_1_0_integrity_spec.rb` requires only
`digest`/`pathname`/`spec_helper`, so it is picked up by `bundle exec rspec` in the `test` job — app
suite is now 62 spec files, `276 examples, 0 failures`. Gem: picked up by `bundle exec rspec` in the
new `rspec` job — `67 examples, 0 failures`. Both also pass **standalone** (`1 example, 0 failures`
each), so there is no load-order dependency: the gem file requires nothing, but the gem's `.rspec` has
`--require spec_helper` and `spec/spec_helper.rb:3,5` requires `digest` and `pathname`. Good.

**Survives the J.5 rollback.** Neither copy references `MoodProbe` at all — they are pure
`Digest`/`Pathname`. They cannot be affected by the app returning to gem `v0.1.0`. Not selected into
the essentia job either (no `:essentia` text, and Rails-free regardless).

**Correctly not** asserting `baseline == golden` — those must diverge at slice 5. And it converts
silent drift into an explicit two-file edit (JSON + hardcoded digest) that a reviewer will see. True
immutability is not achievable in-repo; this is the right ceiling.

#### SHOULD-FIX 2 — the guard protects the bytes but not the instruction

`baseline_dir.glob("*.json")` leaves `README.md` — the file carrying E.1's mandated retirement
sentence, the thing SHOULD-FIX 3 existed to put there — completely unguarded. It can be deleted or
rewritten with the suite staying green, in both repos. E.1 `:546` requires that sentence to live in
the directory *because* "the observed response to an obstacle with no documented exit is to remove the
obstacle"; the mechanism built to make E.1 mechanical does not defend the exit route. One line fixes
it: assert the full directory listing (`baseline_dir.children.map(&:basename)`) instead of only
`*.json`, or add `README.md` to the digest map.

**Correcting your pre-verification, as asked:** "also asserts the FILE SET so a deletion fails" is
true for **JSON** deletions only. `README.md` deletion, non-JSON additions, and nested additions all
pass. Everything else you listed I found correct — `*.json` not `*` ✅, app `.rspec` requires only
`spec_helper` ✅, 62 app spec files ✅, gem workflow no longer pins a ruby-version ✅, `PLATFORMS`
includes `x86_64-linux` ✅, `v0.1.0` peels to `5360f8f` and `ls-remote --tags origin` is empty ✅,
suites 276/0 and 67/0 ✅.

#### SHOULD-FIX 3 — a new boundary was introduced with no documentation, and it narrows the deferred F.2 mirror

The job now enforces an invariant the design never states: **`:essentia` specs must be Rails-free.**
That is a sound call given the job has no postgres, and I am not asking for it to be reversed. Two
problems:

1. **It is documented only by a runtime error string.** The round-1 comment was deleted (correctly —
   its claim was false) and not replaced, so the block's most consequential rule is invisible until
   CI fails. `CLAUDE.md` change discipline: *"If introducing a boundary, document why it is needed in
   code comments or PR notes."*
2. **It constrains a deferred item.** Design F.2 `:770-773` argues the app-side mirror is worth having
   precisely because it "makes the assertion an **integration-level claim** as well as a unit one."
   Whoever writes it must now keep it Rails-free or change the job. That is a legitimate outcome, but
   it is a narrowing of J.3 item 8's other half decided in this slice and recorded nowhere.

Record the constraint against slice 5's F.2 item and add the comment.

---

### R5 — Does the slice now satisfy its defining property: every item correct AND green after the app returns to gem tag `v0.1.0`?

**Yes.** This is the question I answered NO to in round 1, and the NO was solely about the app's
`ci.yml`.

| Item | Green now | Correct after rollback to gem `v0.1.0` |
| --- | --- | --- |
| `.github/dependabot.yml` | ✅ unchanged since round 1 | ✅ bot config, gem-API-independent |
| `baseline_v0_1_0/*.json` (both repos) | ✅ | ✅ v0.1.0 returns exactly these six rescaled heads |
| `baseline_v0_1_0/README.md` (both repos) | ✅ | ✅ prose, now verbatim-correct |
| `spec/baseline_v0_1_0_integrity_spec.rb` (both repos) | ✅ 276/0 and 67/0 | ✅ pure `Digest`/`Pathname`, references no gem API |
| gem `.github/workflows/ci.yml` | reading only — see below | ✅ `bundle exec rspec` / `rubocop`; an app rollback does not move gem `main`, so slices 2–3 stay enforced |
| gem `Gemfile.lock` `PLATFORMS` | ✅ | ✅ inert — see R6 |
| app `.github/workflows/ci.yml` | ✅ **was ❌** | ✅ reverting item 12 restores `:essentia` on a `spec_helper`-only file, so discovery finds it, the Rails-free check passes, `floor=5`, `expected=5` |

**Gem CI, by reading only as instructed.** Both jobs now omit `ruby-version`, so `ruby/setup-ruby@v1`
falls back to a version file. The gem has **no `.ruby-version`**; it has `.tool-versions`
(`ruby 4.0.1`, `python 3.11.6`), which setup-ruby does support and from which it reads only the ruby
line. `x86_64-linux` in `PLATFORMS` is what lets `bundle install` resolve on an ubuntu runner —
without it, a lockfile listing only `arm64-darwin-25` and `ruby` is the classic linux-CI failure. Both
changes are the right ones for MF-4. I make **no claim** about whether the workflow passes on GitHub;
it has never executed.

Local evidence that the two commands those jobs run are green at gem HEAD: `67 examples, 0 failures`;
`30 files inspected, no offenses detected`.

---

### R6 — New scope creep or runtime change from the fixes?

**No scope creep. No runtime change. The lockfile edit is inert.**

Full-slice file lists (`BASE..HEAD`), 8 files per repo — the round-1 set plus exactly one new spec
file each, plus the gem lockfile line:

```
app: .github/dependabot.yml · .github/workflows/ci.yml · spec/baseline_v0_1_0_integrity_spec.rb
     spec/fixtures/mood_probe/baseline_v0_1_0/{README.md,chirp,clicks,sine_440,white_noise}.json
gem: .github/workflows/ci.yml · Gemfile.lock · spec/baseline_v0_1_0_integrity_spec.rb
     spec/fixtures/mood_probe/baseline_v0_1_0/{README.md,chirp,clicks,sine_440,white_noise}.json
```

Still zero changes under `app/`, `lib/`, `config/`, `python/`, `exe/`, `db/`, the app's `Gemfile` or
`Gemfile.lock`, or any `.gemspec`. No registry, planner, mapper, or Python edit. No G1 spec, no F.2
mirror, no `essentia_offline`/`essentia_golden` job. `Gemfile:34` is still `branch: "main"`.

**The lockfile line is inert at runtime, twice over.** The delta is one line and nothing else:

```
$ git -C <gem> diff -U0 5360f8f..ac8f24b -- Gemfile.lock
@@ -57,0 +58 @@ PLATFORMS
+  x86_64-linux
```

No `GEM`/`specs`/version line moved, so no dependency resolution changes for the gem's own
development. And the app never reads it: for a git-sourced gem Bundler resolves from the gemspec, and
the app's own `Gemfile.lock` is untouched in this slice. `PLATFORMS` also affects only install-time
resolution, never loaded code.

The new integrity spec is likewise inert for consumers — the gemspec packages only `LICENSE.txt`,
`NOTICE`, `README.md`, `exe/*`, `lib/**/*.rb`, `python/*.py`, so nothing under `spec/` ships.

One thing I would ordinarily call creep and am **not**: the Rails-free rejection is new logic the
design never asked for. It is load-bearing for MF-1 and I accept it — but it needs the documentation
and the recorded consequence in SHOULD-FIX 3.

---

## Findings, ranked

| # | Rank | Finding | Location |
| --- | --- | --- | --- |
| 1 | SHOULD-FIX | `grep -rlE "(:essentia\|essentia:…)"` is not equivalent to RSpec's `--tag` selection. **Under-includes** any tag applied outside literal `*_spec.rb` text (`define_derived_metadata`, shared groups in `spec/support/**`) — proven green with a spec never run, and the floor cannot catch it because the golden spec alone satisfies it. **Over-includes** on the missing word boundary — `let(:essentia_mapper)` (J.3 items 1/15) turns the job red with a misleading message. A `\b` fixes the second half. | `vibe-doctor/.github/workflows/ci.yml:118` |
| 2 | SHOULD-FIX | Integrity spec globs `*.json`, so `README.md` — the file carrying E.1's mandated retirement sentence — can be deleted or rewritten with the suite green. Stray non-JSON and nested JSON also uncaught. Assert the full directory listing. | `spec/baseline_v0_1_0_integrity_spec.rb:17` (both repos) |
| 3 | SHOULD-FIX | New undocumented boundary: "`:essentia` specs must be Rails-free." Documented only by a runtime error string (round-1 comment deleted, not replaced), against `CLAUDE.md`'s "document why a boundary is needed". It also narrows the deferred F.2 mirror, which design F.2 `:770-773` wants as an integration-level claim. Record against slice 5. | `vibe-doctor/.github/workflows/ci.yml:116-121` |
| 4 | NIT | Gem CI now depends on setup-ruby reading `.tool-versions`; the app uses a `.ruby-version` file. Supported, and the right fix for MF-4, but "mirror the shape" (F.3) would be exact with a `.ruby-version`. Unverifiable until pushed. | `mood_probe/.github/workflows/ci.yml:16,31` |
| 5 | NIT | Carried from round 1: G1's author must glob `*.json`, not `*` — `README.md` shares the directory. The new integrity spec already models the correct idiom. | `baseline_v0_1_0/` (both repos) |

Round-1 NIT 7 (double RSpec boot) **withdrawn** — the load set is one Rails-free file now.

**No ambiguity to escalate. No re-tier** — risk triggers unchanged from round 1: external automation
config plus two test-only spec files and one lockfile `PLATFORMS` line. No migration, authz change,
data exposure, destructive op, runtime integration, or new dependency.

**Deferred items confirmed still absent and correctly so:** no G1 parity spec, no F.2 mirror, no gem
`essentia_offline`/`essentia_golden`, tag still unpushed. Not filed. No `command_runner_spec` or
CI-hardening comment made. No hardcoded example count asserted anywhere in this review — the gate I
applied is zero failures.

---

## Evidence

**Ranges reviewed**
- Round-1→2 delta: app `9e28d3f..52141f6`, gem `f0f8127..ac8f24b`
- Whole slice re-checked for scope: app `a99c397..52141f6`, gem `5360f8f..ac8f24b`
- `git status --porcelain` empty in both repos.

**Documents re-read:** design `§E.1 :493-547`, `§F.2 :751-783`, `§F.3 :785-804`, `§J.3 :946-984`,
`§J.4 :1030-1083`, `§J.5 :1085-1097`; `/Users/lukeolson/projects/vibe-doctor/CLAUDE.md` (change
discipline, testing expectations); my own round-1 report.

**Commands and real output**

Scope, and the lockfile delta:
```
$ git -C <app> diff --stat 9e28d3f..52141f6
 .github/workflows/ci.yml                           | 25 ++++++++++++++++------
 spec/baseline_v0_1_0_integrity_spec.rb             | 24 +++++++++++++++++++++
 spec/fixtures/mood_probe/baseline_v0_1_0/README.md |  5 ++++-
$ git -C <gem> diff --stat f0f8127..ac8f24b
 .github/workflows/ci.yml                           |  2 --
 Gemfile.lock                                       |  1 +
 spec/baseline_v0_1_0_integrity_spec.rb             | 20 ++++++++++++++++++++
 spec/fixtures/mood_probe/baseline_v0_1_0/README.md |  5 ++++-
$ git -C <gem> diff -U0 5360f8f..ac8f24b -- Gemfile.lock
@@ -57,0 +58 @@ PLATFORMS
+  x86_64-linux
```

MF-1 closed — job body, real app tree, database unreachable:
```
errors_outside=0
floor=5 expected=5
DISCOVERY+FLOOR OK WITH NO DATABASE
EXIT=0
```
(Round 1, same command shape: `example_count=0, errors_outside_of_examples_count=60`, real run exit 1.)

Discovery on the real tree, and the absence of collisions today:
```
$ grep -rlE "(:essentia|essentia:[[:space:]]*true)" spec --include="*_spec.rb" | sort
spec/integration/essentia_extract_golden_spec.rb
$ grep -l "rails_helper" spec/integration/essentia_extract_golden_spec.rb; echo $?
1
$ find spec/fixtures/mood_probe/golden -maxdepth 1 -type f -name "*.json" | wc -l
4
$ grep -rn "essentia" spec --include="*_spec.rb" | grep -v essentia_extract_golden
# 11 lines across 5 files, all of the form mood_source: "essentia_itunes" / "essentia_youtube"
# none match the discovery pattern
```

MF-2 controls (scratch harness, real RSpec, 4 golden JSONs so `floor`=5):
```
tag intact:                floor=5 expected=5   exit 0     (passing control, just inside the bound)
tag renamed :essentia_offline: floor=5 expected=0   exit 1  (floor catches it)
tag text removed entirely: grep empty → pipefail/set -e abort, exit 1
```

R1(a) under-inclusion, real RSpec vs grep, then the exact job body:
```
$ grep -rlE "(:essentia|…)" spec --include="*_spec.rb"      → 1 file
$ rspec --tag essentia --dry-run --format json              → example_count=6, 2 files
$ <exact job body>  floor=5 expected=5 → "5 examples, 0 failures" → FULL_JOB_BODY_EXIT=0
```

R1(b) over-inclusion, exact job body with an untagged `rails_helper` mapper spec:
```
DISCOVERED: essentia_extract_golden_spec.rb, essentia_mapper_spec.rb
Essentia specs must remain Rails-free in this no-database job
JOB_BODY_EXIT=1
```

R4 integrity-spec scenarios (repo spec verbatim, `sed`-redirected to a scratch copy of the real
directory; no repo file touched):
```
unmodified:        1 example, 0 failures
one-byte edit:     1 example, 1 failure
json deleted:      1 example, 1 failure
stray json added:  1 example, 1 failure
README deleted:    1 example, 0 failures     <-- gap
README rewritten:  1 example, 0 failures     <-- gap
stray .txt added:  1 example, 0 failures     <-- gap
nested json added: 1 example, 0 failures     <-- gap
```

R3 README verbatim:
```
$ diff <(sed -n '541,544p' design.md) <(sed -n '6,9p' <app>/…/README.md)   → IDENTICAL
$ diff <(sed -n '541,544p' design.md) <(sed -n '6,9p' <gem>/…/README.md)   → IDENTICAL
$ cmp <app>/…/README.md <gem>/…/README.md                                  → identical
```

Suites and lint at the new HEADs (gate = zero failures):
```
app: 276 examples, 0 failures   ·  rubocop: 201 files inspected, no offenses detected
gem:  67 examples, 0 failures   ·  rubocop:  30 files inspected, no offenses detected
app integrity spec standalone: 1 example, 0 failures
gem integrity spec standalone: 1 example, 0 failures
app spec files: 62
```

**What I did not do:** I did not rebuild the amd64 Essentia image, so the real-Essentia half of the
job rests on the implementer's reported run and your pre-verification; I proved the load-time root
cause instead. I made no assessment of whether the gem workflow passes on GitHub. **No file in either
repo was modified** — all mutation testing happened on copies under the session scratchpad, and every
repo command was read-only.

VERDICT: APPROVE-WITH-CHANGES
