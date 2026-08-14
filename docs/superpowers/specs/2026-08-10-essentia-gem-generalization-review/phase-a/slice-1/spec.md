# ESSENTIA-GEM-V2 Phase A — Slice 1 SPEC REVIEW

**Reviewer:** Plumb (Spec Reviewer) · **Tier:** 1 · **Scope:** exactly the two diffs below, read-only.

- app: `/Users/lukeolson/projects/vibe-doctor` `a99c397..9e28d3f` (7 files)
- gem: `/Users/lukeolson/projects/gems/mood_probe` `5360f8f..f0f8127` (6 files)

Deferred items 1–4 from the dispatch (G1 parity spec, F.2 app mirror, gem
`essentia_offline`/`essentia_golden`, unpushed tag) are **not** filed as findings.

**VERDICT: REJECT** — one MUST-FIX breaks a CI job this slice was supposed to fix, and a second
strips the anti-silent-skip property F.3 says "must be kept". Both are inside the delivered half of
J.3 item 8. Everything else in the slice is correct, and items 7 and 14 are exemplary.

---

## Answers

### S1 — Does the diff deliver exactly J.3 items 7, 8 (SF-1 half), 14, plus gem `rspec` + `lint`?

**Scope is exactly right. One of the four items is delivered broken.**

| Item | Required | Delivered | Verdict |
| --- | --- | --- | --- |
| **7** — `.github/dependabot.yml` `ignore` for `mood_probe` (M7) | app | `ignore: - dependency-name: mood_probe`, attached to the **bundler** entry (not github-actions) | ✅ correct |
| **8** — `ci.yml:117-123` example-count arithmetic + spec selection (SF-1) | app | `--tag essentia` selector; expected count from an RSpec JSON dry run | ❌ **MUST-FIX 1 + 2** |
| **14** — frozen `baseline_v0_1_0/*.json` + retirement comment | both repos | 4 JSON + `README.md`, byte-identical to `golden/` and across repos | ✅ bytes; ⚠️ SHOULD-FIX 3 on the comment |
| **F.3 gem `rspec` + `lint`** (Principal Q4 finding 2) | gem | new `.github/workflows/ci.yml`, two jobs, `pull_request` + `push: [main]` | ✅ correct, one NIT |

**Nothing present that should not be.** `git diff --name-only` on both ranges lists only those 13
files. No `lib/`, `app/`, `config/`, `python/`, `Gemfile`, `Gemfile.lock`, `exe/`, or spec-code file
is touched. No registry, planner, mapper, or Python edit. No `essentia_offline`/`essentia_golden`
job. No G1 spec. No F.2 mirror. `Gemfile:34` is still `branch: "main"` — correct, item 6 is a
behaviour-commit change.

**Nothing missing from the four in-scope items** — item 7 and 14 are complete; item 8 and the gem
jobs are present but defective as detailed below.

---

### MUST-FIX 1 — The new `--tag essentia` selector makes the app's `essentia` job go RED

`.github/workflows/ci.yml:118,120` — the old command named exactly one file:

```
bundle exec rspec spec/integration/essentia_extract_golden_spec.rb
```

That file is **the only one of the app's 61 spec files that does not require `rails_helper`** (it
requires `spec_helper` + `mood_probe` only). The new command passes **no file argument**, so RSpec
falls back to its default `spec/**/*_spec.rb` pattern and loads all 61 — 60 of which require
`rails_helper`, which calls `ActiveRecord::Migration.maintain_test_schema!` at
`spec/rails_helper.rb:36`.

The `essentia` job has **no `postgres` service and no `DATABASE_URL`** (contrast the `test` job,
`ci.yml:69-85`, which has both plus `bin/rails db:test:prepare`). The container's only env is
`-e ESSENTIA_SPECS=1 -e RAILS_ENV=test`. `config/database.yml` is `adapter: postgresql`.

Reproduced locally by pointing `DATABASE_URL` at a dead port — the same failure the container will
hit with no server at all:

```
$ DATABASE_URL="postgres://nobody:nobody@127.0.0.1:59999/nonexistent_db" \
  ESSENTIA_SPECS=1 RAILS_ENV=test bundle exec rspec --tag essentia --dry-run --format json
summary={"duration"=>3.6e-05, "example_count"=>0, "failure_count"=>0,
         "pending_count"=>0, "errors_outside_of_examples_count"=>60}

An error occurred while loading ./spec/jobs/enrich_album_job_spec.rb.
Failure/Error: ActiveRecord::Migration.maintain_test_schema!
ActiveRecord::DatabaseConnectionError: ... PG::ConnectionBad: connection refused
# ./spec/rails_helper.rb:36

$ ... bundle exec rspec --tag essentia --format documentation; echo $?
1
```

`expected` becomes `0`, the real run exits `1`, `test "$status" -eq 0` fails, **the job fails**. This
is a loud red, not a silent pass — but it is still a broken CI job introduced by the one slice whose
defining property is "no behaviour change, everything green." It also survives the J.5 rollback in
exactly this broken state (see S5).

Secondary aggravator, same root cause: booting Rails in that image is itself new. `/config/master.key`
is dockerignored (`.dockerignore:14`), so the essentia image has never loaded
`config/environment` — the old single-file command never required it. Fixing only the database would
still be entering untested territory for that image.

The SF-1 goal is achievable without loading Rails: widen the selection to the `:essentia`-tagged
specs **within a bounded, Rails-free set** (e.g. keep an explicit path list or
`--pattern "spec/integration/essentia_*_spec.rb"` alongside `--tag essentia`), or give the job a
database. Reviewer's note, not a prescription — the choice is the implementer's.

---

### MUST-FIX 2 — Deriving `expected` from the same selector deletes the anti-silent-skip property

§F.3 (design `:801-804`): *"The count assertion is a good anti-silent-skip device and **must be
kept** — but adding examples to that file breaks the arithmetic … Widen to a `--tag` selector and
derive the expected count from something that does not move when fixtures are added."*

The old count was an **independent oracle**: `ls golden/*.json | wc -l + 1`, sourced from the
filesystem. The new count is sourced from RSpec's own collection of the identical selector, so it
can never disagree with it. Zero collected examples therefore *passes*:

```
$ bash -c 'expected=$(ESSENTIA_SPECS=1 bundle exec rspec --tag no_such_tag --dry-run --format json \
    | ruby -rjson -e "puts JSON.parse(STDIN.read).fetch(\"summary\").fetch(\"example_count\")"); \
  output=$(ESSENTIA_SPECS=1 bundle exec rspec --tag no_such_tag --format documentation); status=$?; \
  test "$status" -eq 0 && grep -qE "^${expected} examples, 0 failures$" <<< "$output"; echo $?'
expected=[0]
All examples were filtered out
0 examples, 0 failures
GATE_RESULT_EXIT=0      # <-- GREEN with nothing run
```

This is live, not theoretical: **J.3 item 12 rewrites `spec/integration/essentia_extract_golden_spec.rb`**
(`MOOD_HEADS` → requested descriptor list, `analyze` arity). That is the file carrying the
`:essentia` tag on its `describe` (`:16`). If item 12 drops or renames the tag, or a future
`spec_helper` change stops `ESSENTIA_SPECS=1` from lifting
`config.filter_run_excluding essentia: true` (`spec/spec_helper.rb:17`), the app's strongest gate
goes green having executed nothing — in the same slice that regenerates the goldens.

The in-diff comment asserts the opposite: *"Derive the expected count from every :essentia example so
new specs cannot be silently skipped"* (`ci.yml:115`). The mechanism does not support the claim.

The half of SF-1 that **is** satisfied, for the record: the count no longer breaks when a fixture is
added, because `DECODABLE_FIXTURES` drives both the examples and the derived count. Only the oracle
was lost. A nonzero floor (`test "$expected" -ge 5`) or any source outside the selector restores it.

---

### S2 — Does `README.md` inside the frozen directory satisfy E.1?

**The placement does. The content does not — it is a lossy paraphrase that drops E.1's two operative
clauses.**

On placement: E.1 `:546` says *"Put that sentence in **the directory's header comment**"* — the
directory's, not the JSON's. JSON has no comment syntax, and E.1 `:500` simultaneously requires the
four files *"unchanged"*. A sibling `README.md` is the only construction that honours both, and it
keeps the frozen bytes byte-identical to `golden/` (verified below), which is what G1 will diff
against. **Correct call, no finding.**

On content — E.1's required sentence (`:541-544`) against what shipped:

| E.1 requires | In README? |
| --- | --- |
| frozen pre-`v0.2.0` output, never rewritten | ✅ |
| retirement = a new dated baseline directory (`baseline_<version>/`) | ✅ ("new dated sibling directory") |
| the old directory **kept** | ⚠️ implied only |
| **"Never an edit to, or *deletion of*, `baseline_v0_1_0/`"** | ❌ deletion never named |
| **rationale in the commit message: upstream model version, old and new values, who reviewed the delta** | ❌ absent entirely |
| first legitimate cause is an upstream model-version bump | ❌ absent |

#### SHOULD-FIX 3 — the README omits the deletion prohibition and the whole commit-message rationale

Shipped text (identical in both repos, `README.md:1-6`):

```
These JSON files are frozen pre-v0.2.0 output copied byte-for-byte from the sibling `golden/` directory.
They must never be regenerated, rewritten, or edited.
Retire this baseline only by adding a new dated sibling directory. Never modify this directory in place.
```

"Never modify this directory in place" does not forbid `git rm -r`. E.1 added the words *"or deletion
of"* for a stated reason (`:547`): *"The observed response to an obstacle with no documented exit is
to remove the obstacle."* **Removal is the exact verb the paraphrase dropped.** And the four
accountability requirements — model version, old values, new values, named reviewer — are the
substance of the retirement procedure; without them "add a new dated directory" is satisfiable by
anyone who dislikes a red gate.

Why this is more than pedantry: `grep -rn baseline_v0_1_0` over the **gem** repo returns
**nothing outside the directory itself**. The design doc lives only in the app. In the gem, this
README is the *sole* institutional record of the retirement procedure, permanently. Quote E.1's
blockquote verbatim.

---

### S3 — Immutable by construction, or only by convention?

**Only by convention. There is nothing — and per your instruction, this is recorded now.**

Verified absent in **both** repos:

- No `CODEOWNERS` (`.github/CODEOWNERS` and `CODEOWNERS` both absent in both repos).
- No `.gitattributes` in the gem; the app's `.gitattributes` carries no protection for this path.
- No spec, rake task, or CI step asserting the baseline's existence, count, or hashes. `grep -rn
  baseline_v0_1_0` finds **zero** executable references in either repo — app hits are the design doc
  and an earlier review only; the gem has zero hits at all.
- No filesystem or git mechanism (no submodule, no LFS pin, no pre-commit hook).

**Direct answer to your J.3-item-11 question: nothing in this diff would stop a directory glob.**
Today both generators write literal paths and are safe:

- `vibe-doctor/spec/fixtures/mood_probe/generate_goldens.rb:7,20` — `golden_dir = root.join("spec/fixtures/mood_probe/golden")`, then `golden_dir.join("#{fixture_name}.json").write(...)`
- `mood_probe/spec/fixtures/mood_probe/generate_goldens.rb:7,19` — `fixture_root = Pathname(__dir__)`, then `fixture_root.join("golden/#{name}.json").write(...)`

Note the gem generator's `fixture_root` is already the **parent** of both directories. A rewrite that
switches to `fixture_root.glob("*/*.json")`, or that iterates fixture subdirectories to handle the
new multi-descriptor payload, walks straight into `baseline_v0_1_0/`. The sibling placement (E.1
`:506`) protects the app's *example-count arithmetic*; it does not protect the *bytes*.

Two amplifiers specific to this diff:

1. **The gem side is unguarded for longer than the app side.** The gem has a `fixtures_spec.rb`
   asserting `golden/` by name (`spec/fixtures_spec.rb:7-12`) — and no equivalent for the baseline.
   Per the Principal's Q3 (`:143-146`), the gem's G1 copy is not even scheduled yet. So from now
   until at least slice 3, a silent gem-side baseline edit or deletion fails **no** test anywhere.
2. **The only current reader will be G1, which does not exist yet.** Between this commit and slice 5,
   a corrupted baseline is invisible; when G1 finally reads it, a green G1 proves parity against
   whatever the file says *then*, not against v0.1.0.

#### SHOULD-FIX 4 — add one mechanical guard now

A ~5-line pure-Ruby spec pinning the four SHA-256 digests (and asserting the directory holds exactly
those four JSON files) would run in the app `test` job and the new gem `rspec` job today, needs no
Essentia, no models, no Docker, and survives the J.5 rollback unchanged — the same properties that
qualified everything else in this slice. Digests independently computed at HEAD:

```
b2a04b178b125e9ea823d122288472f9dc0665af3d44124bc38829b95131a0fb  chirp.json
50c7ee158661219c41dc54c7eda799bbf7529a60f995bdde62fd5796ba7c2c84  clicks.json
1c4bfbc2bc42a54d10c73d6492252012c43be9b4c88fe5171dcab258036fdbb9  sine_440.json
7a17251f3bad130b25292c03dbcff13ea89da8f0b8e2a35ae7c1ad40140915a3  white_noise.json
```

I am **not** asserting the design requires this (E.1 asks for a comment, and the comment is there),
so it is SHOULD-FIX and not MUST-FIX. But "the irreversible half" is the stated purpose of this
slice, and right now the irreversible asset is defended by a paragraph of prose. At minimum, carry
this forward as a **mandatory review item on J.3 item 11** — the Principal already asked for exactly
that (`principal-sequencing.md:104`): *"Check the generator's write scope explicitly excludes
`baseline_v0_1_0/` when item 11 is reviewed."*

---

### S4 — Does anything change runtime behaviour of either the app or the gem?

**No. Confirmed by enumeration, not by reading the report.**

The 13 changed files are: 2 CI/bot config files in the app, 1 new CI config in the gem, and 10
fixture/doc files under `spec/fixtures/`. Not one file is loaded by the app or the gem at runtime.

- **Zero** changes under `app/`, `lib/`, `config/`, `python/`, `exe/`, `db/`, `Gemfile`,
  `Gemfile.lock`, or any `*.gemspec`. No migration, no initializer, no dependency.
- The four new JSON files and the README are read by **no** code path: `grep -rn baseline_v0_1_0`
  returns no executable reference in either repo (S3).
- No existing glob absorbs the new directory. Both golden specs bind `golden/` explicitly
  (`vibe-doctor/spec/integration/essentia_extract_golden_spec.rb:19`,
  `mood_probe/spec/integration/essentia_golden_spec.rb:26`), as does `mood_probe/spec/fixtures_spec.rb:11`.
  The one glob that *did* enumerate a fixture directory — `ls golden/*.json | wc -l` in the app's
  `ci.yml` — was removed by this diff, so the SF-1 hazard E.1 `:506-510` warned about is closed on
  both sides.
- The gem tag `v0.1.0` is an annotated tag at `5360f8f` (= BASE); it adds no commit and moves nothing.

Zero failures in both suites at HEAD (never a hardcoded count — the gate is 0 failures):

```
$ cd /Users/lukeolson/projects/vibe-doctor && bundle exec rspec
275 examples, 0 failures

$ cd /Users/lukeolson/projects/gems/mood_probe && bundle exec rspec
66 examples, 0 failures
$ bundle exec rubocop
29 files inspected, no offenses detected
```

The one thing that *did* change observable behaviour is **CI**, not runtime — and it changed for the
worse (MUST-FIX 1).

---

### S5 — Would this commit survive the J.5 rollback intact, every item still correct and green?

**Three of four items: yes, cleanly. Item 8: it survives, but survives broken.** File by file, under
"revert the behaviour commit, `Gemfile` → `tag: "v0.1.0"`, nothing else":

| File | Survives? | Still correct at gem v0.1.0? |
| --- | --- | --- |
| `.github/dependabot.yml` | ✅ | ✅ Independent of the gem's API — pure bot config. This is the item J.5 `:1088-1090` most cares about, and the Principal's Q4 calls it *"the thing that stops slices 2 and 3 leaking into the app"* (`:190`). Correct as written, on the bundler entry. |
| `spec/fixtures/mood_probe/baseline_v0_1_0/*.json` (app) | ✅ | ✅ At v0.1.0 `analyze` returns `Features` with these six rescaled heads, which is exactly what these bytes hold. Unread by anything, so unbreakable. |
| `.../baseline_v0_1_0/README.md` (app) | ✅ | ✅ Prose, still accurate (content gap = SHOULD-FIX 3). |
| gem `baseline_v0_1_0/*` + `README.md` | ✅ | ✅ Lives in the gem repo's `main`, outside `spec.files` (gemspec `:18-25`), so the app's rollback cannot touch it. It is the anchor for the gem's own A8 rescale — the load-bearing reason E.1 `:522` said "both repos". |
| gem `.github/workflows/ci.yml` | ✅ | ✅ `bundle exec rspec` / `bundle exec rubocop` are version-agnostic and both pass at gem HEAD today (above). A rollback of the *app* does not move gem `main`, so slices 2–3 stay enforced — the exact hole the Principal's Q4 finding 2 opened this job to close. |
| app `.github/workflows/ci.yml` | ✅ | ❌ **Survives broken.** The `:essentia` tag still resolves after a revert (item 12's edits to the tagged file are undone, `describe … :essentia` restored), so the *selector* is rollback-safe. But per MUST-FIX 1 the job is red **now** and stays red through the rollback. J.5's rationale for keeping the I commit is that its contents are *"guardrails against exactly the situation a rollback implies"* (`:1089-1090`). A permanently red job is not a guardrail — it is the thing a team learns to ignore, which is the same failure mode the Principal rejected for G1 (`:131-133`). |

Verified rollback anchor:

```
$ git -C /Users/lukeolson/projects/gems/mood_probe for-each-ref refs/tags \
    --format='%(refname:short) %(objecttype) %(subject)'
v0.1.0 tag mood_probe v0.1.0 rollback anchor
$ git rev-parse v0.1.0^{}
5360f8fd8609eae39edb5dfab8a07f6439a0b137     # == gem BASE, not re-pointed
$ git ls-remote --tags origin
(empty — remote reachable, zero tags; local-only as intended)
```

**Not filed as a finding** (dispatch item 4), but stated so S5 closes honestly: J.5 step 2 is not
*executable* until `v0.1.0` is pushed — `Gemfile.lock` resolves `mood_probe` from
`https://github.com/Lhosb/mood_probe.git`, and `bundle install` against a tag absent from that
remote fails. The tag exists locally and correctly; the push is with the Manager for the user.

**So: fix MUST-FIX 1 and this slice's defining property holds for all four items.** Nothing else in
the slice needs to change for the rollback to be safe.

---

## Findings, ranked

| # | Rank | Finding | Location |
| --- | --- | --- | --- |
| 1 | **MUST-FIX** | `--tag essentia` with no file argument loads all 61 spec files; 60 require `rails_helper` → `maintain_test_schema!` → `PG::ConnectionBad`. The `essentia` job has no postgres service. Job goes red; stays red through the J.5 rollback. | `vibe-doctor/.github/workflows/ci.yml:118,120` |
| 2 | **MUST-FIX** | `expected` derived from a dry run of the *same* selector is not an independent oracle. Zero collected examples ⇒ `0 examples, 0 failures` ⇒ gate exits 0. Loses the property §F.3 says "must be kept"; the in-diff comment claims otherwise. Live risk once item 12 rewrites the tag-bearing spec. | `vibe-doctor/.github/workflows/ci.yml:115,118,122` |
| 3 | SHOULD-FIX | Retirement README omits E.1's two operative clauses: the **deletion** prohibition ("or deletion of"), and the commit-message rationale (upstream model version, old and new values, named reviewer). In the gem repo this README is the only record of the procedure. | `baseline_v0_1_0/README.md:5` (both repos) |
| 4 | SHOULD-FIX | Baseline is immutable by convention only: no CODEOWNERS, no hash spec, no CI check, zero executable references in either repo. Nothing stops a J.3-item-11 glob. Gem side is unguarded until at least slice 3. | both repos, `spec/fixtures/mood_probe/baseline_v0_1_0/` |
| 5 | NIT | Gem CI pins `ruby-version: "3.2"`, but `.tool-versions` says `ruby 4.0.1` and the consuming app's image is `RUBY_VERSION=4.0.1` (`Dockerfile:11`). The gemspec floor is `>= 3.2` so 3.2 is legitimate, but the app's own workflow pins nothing and inherits `.ruby-version` — §F.3 says "mirror the shape". As written, the job enforcing slices 2–3 never exercises the Ruby the gem actually runs on. `Gemfile.lock` also declares `BUNDLED WITH 4.0.3`, untested on 3.2. | `mood_probe/.github/workflows/ci.yml:18,33` |
| 6 | NIT | `README.md` now sits among the fixture JSONs, so `baseline_v0_1_0/*` is no longer all-JSON (visible in the implementer's own `shasum … /*` output, which digested the README). A G1 spec globbing `*` rather than `*.json` will try to `JSON.parse` prose. Same class of hazard as E.1's placement note. | `baseline_v0_1_0/README.md` (both repos) |
| 7 | NIT | The gate now boots RSpec twice (dry run + real run), doubling the job's load cost — and after MUST-FIX 1, doubling a full Rails boot. | `vibe-doctor/.github/workflows/ci.yml:118-119` |

**No ambiguous requirements to escalate.** E.1, F.3, and J.3 items 7/8/14 each read one way, and the
dispatch already settled the two genuinely contested boundaries (the G1 split and the F.2 relocation).

**No re-tier.** Risk triggers touched: external automation config only (Dependabot, GitHub Actions ×2).
No migration, no authz change, no new data exposure, no destructive op, no runtime external
integration, no new dependency. Tier 1 remains correct — arguably generous, except that MUST-FIX 1
is precisely the kind of defect a full chain exists to catch.

---

## Evidence

**Diff ranges reviewed**
- app `a99c3973a40ebd075469a0d841cbcf09b4e4809c..9e28d3fd5f6442acaa1ee6452865f720d3ab6cfb`
- gem `5360f8fd8609eae39edb5dfab8a07f6439a0b137..f0f8127d94300d08e383e6400be04b0ff4658dd9`
- Both worktrees clean: `git status --porcelain` empty in both.

**Documents read before reviewing** (per dispatch)
- `docs/superpowers/specs/2026-08-10-essentia-gem-generalization-design.md` (branch
  `docs/essentia-gem-v2-design`) — §E.1 `:493-547`, §F.1-F.4 `:742-811`, §J.1 `:911-915`,
  §J.2 `:917-941`, §J.3 `:946-984`, §J.4 `:986-1083`, §J.5 `:1085-1097`
- `/tmp/maestri-reviews/ESSENTIA-GEM-V2/phase-a/slice-1/principal-sequencing.md` (all)
- `/tmp/maestri-reviews/ESSENTIA-GEM-V2/phase-a/slice-1/implementer.md` (all)
- `/Users/lukeolson/projects/vibe-doctor/CLAUDE.md`. No `.github/copilot-instructions.md` and no
  `.github/instructions/*.instructions.md` exist in either repo — noted rather than guessed. The
  CLAUDE.md rules that bear on this diff are "minimal, focused changes that align with existing
  patterns" and "keep tests deterministic": items 7/14 and the gem workflow comply; MUST-FIX 1 is a
  departure from the existing pattern (the essentia job has never booted Rails).

**Files inspected** (beyond the 13 in the diff)
`vibe-doctor`: `.rspec`, `spec/spec_helper.rb`, `spec/rails_helper.rb`, `config/database.yml`,
`Dockerfile`, `.dockerignore`, `Gemfile`, `Gemfile.lock`, `.ruby-version`, `.gitattributes`,
`spec/integration/essentia_extract_golden_spec.rb`, `spec/fixtures/mood_probe/generate_goldens.rb`,
`spec/support/phase3_parity.rb`, full `.github/workflows/ci.yml`.
`mood_probe`: `mood_probe.gemspec`, `Gemfile`, `Gemfile.lock`, `.rubocop.yml`, `.tool-versions`,
`spec/fixtures_spec.rb`, `spec/integration/essentia_golden_spec.rb`,
`spec/fixtures/mood_probe/generate_goldens.rb`, repo root listing.

**Commands run, with real output**

Diff scope — 13 files, nothing outside CI config and fixtures:
```
$ git -C /Users/lukeolson/projects/vibe-doctor diff --name-only a99c397..9e28d3f
.github/dependabot.yml
.github/workflows/ci.yml
spec/fixtures/mood_probe/baseline_v0_1_0/README.md
spec/fixtures/mood_probe/baseline_v0_1_0/chirp.json
spec/fixtures/mood_probe/baseline_v0_1_0/clicks.json
spec/fixtures/mood_probe/baseline_v0_1_0/sine_440.json
spec/fixtures/mood_probe/baseline_v0_1_0/white_noise.json

$ git -C /Users/lukeolson/projects/gems/mood_probe diff --name-only 5360f8f..f0f8127
.github/workflows/ci.yml
spec/fixtures/mood_probe/baseline_v0_1_0/README.md
spec/fixtures/mood_probe/baseline_v0_1_0/{chirp,clicks,sine_440,white_noise}.json
```

Frozen bytes — verified independently of the implementer's report:
```
$ for n in chirp clicks sine_440 white_noise; do cmp -s app/golden/$n.json app/baseline/$n.json …; done
app  chirp: baseline == golden        gem  chirp: baseline == golden        x-repo chirp: identical
app  clicks: baseline == golden       gem  clicks: baseline == golden       x-repo clicks: identical
app  sine_440: baseline == golden     gem  sine_440: baseline == golden     x-repo sine_440: identical
app  white_noise: baseline == golden  gem  white_noise: baseline == golden  x-repo white_noise: identical
README identical across repos? yes
```

E.1's precondition still holds on the frozen bytes (all strictly inside 0..1, so `raw = 8v + 1` is
exact and the clamp was inert — E.1 `:512-516`):
```
chirp.json       valence=0.3902125954627991  arousal=0.4052208662033081  raw_v=4.1217007637
clicks.json      valence=0.6057485342025757  arousal=0.546747624874115   raw_v=5.8459882736
sine_440.json    valence=0.41735291481018066 arousal=0.2622220516204834  raw_v=4.3388233185
white_noise.json valence=0.2260664403438568  arousal=0.7256550788879395  raw_v=2.8085315228
```
This corroborates the Principal's Q3: today's goldens are already rescaled, so a G1 in slice 1 would
error on a missing raw-emomusic key. Its absence here is correct.

Rails/DB coupling introduced by the new selector:
```
$ find spec -name '*_spec.rb' | wc -l                     →  61
$ for f in $(find spec -name '*_spec.rb'); do grep -q rails_helper "$f" || echo "$f"; done
spec/integration/essentia_extract_golden_spec.rb          # the only one, and it is the file
                                                          # the OLD command named explicitly
$ grep -n maintain_test_schema spec/rails_helper.rb       →  36
$ grep -n 'postgres\|DATABASE_URL' .github/workflows/ci.yml
70:      postgres:            # <- the `test` job only
83:      DATABASE_URL: ...    # <- the `test` job only
```
Plus the two reproductions quoted under MUST-FIX 1 and MUST-FIX 2 (dry-run summary
`example_count=0, errors_outside_of_examples_count=60`; real-run exit `1`; and the zero-example
gate exiting `0`).

Baseline guards — all absent:
```
$ ls .github/CODEOWNERS CODEOWNERS .gitattributes        # app
ls: .github/CODEOWNERS: No such file or directory
ls: CODEOWNERS: No such file or directory
.gitattributes
$ ls .github/CODEOWNERS CODEOWNERS .gitattributes        # gem — all three absent
$ grep -rn baseline_v0_1_0 --exclude-dir=.git . | grep -v 'baseline_v0_1_0/'
# app: 6 hits, all in docs/superpowers/specs/**  (design doc + an earlier review)
# gem: 0 hits
$ find .github -type f                                    # gem
.github/workflows/ci.yml
```

Suites at HEAD (gate = zero failures):
```
app: 275 examples, 0 failures
gem:  66 examples, 0 failures  ·  rubocop: 29 files inspected, no offenses detected
```

Rollback anchor: `v0.1.0` annotated tag → `5360f8f` (= gem BASE, not re-pointed);
`git ls-remote --tags origin` empty, confirming local-only.

**No file in either repo was modified.** Every command above is read-only; the only writes were to
`/tmp/maestri-reviews/`. The two RSpec invocations with a bogus `DATABASE_URL` and a bogus `--tag`
touched no database and no file.

VERDICT: REJECT
