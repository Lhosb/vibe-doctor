# ESSENTIA-GEM-V2 Phase A — Slice 1 SPEC RE-REVIEW, ROUND 3

**Reviewer:** Plumb (Spec Reviewer) · scoped to my own round-2 findings · read-only.
Deltas reviewed: app `52141f6..a5f71fd` (2 files), gem `ac8f24b..6c56f29` (1 file). Both trees clean.

**VERDICT: APPROVE** — all three of my round-2 SHOULD-FIXes are CLOSED, each proven against the exact
scenario I filed it on. One new NIT, cosmetic. No scope creep, no runtime change.

---

## My round-2 findings

### SHOULD-FIX 1 (over-inclusion half — word boundary) — **CLOSED**

Pattern is now `(:essentia\b|essentia:[[:space:]]*true\b)`. The near-certain slice-5 collision I filed
it on is gone, and no legitimate tagging form regressed:

```
let(:essentia_mapper) { described_class.new }        → no      (was MATCH in round 2)
RSpec.describe "goldens", :essentia do               → MATCH
RSpec.describe "x", essentia: true do                → MATCH
real spec/integration/essentia_extract_golden_spec.rb → MATCH
full discovery over the real tree                    → exactly 1 file (the golden spec)
```

So `let(:essentia_mapper)` / `subject(:essentia_mapper)` from J.3 items 1/15 can no longer turn the
job red. Verified with BSD grep on this Mac; the container is Debian (GNU grep), where `\b` in ERE is
likewise supported, and the implementer re-ran the hardened body in the actual amd64 image (5 examples,
0 failures, no PostgreSQL) — that run is the authoritative check for the container's grep.

Residual, **not** a finding: a `rails_helper` spec that mentions the bare token `:essentia` in a comment
still matches and still exits 1. Unlike round 2 the message is now accurate — that file genuinely does
contain `:essentia` and does require `rails_helper`, and it names the path. The under-inclusion half is
deferred per your ruling.

### SHOULD-FIX 2 (README unguarded — you asked me to verify completeness) — **CLOSED, all four**

`Dir.children(baseline_dir).sort` against a key set that now includes `README.md`, plus README's digest
pinned. Repo spec run verbatim (only the `let(:baseline_dir)` line `sed`-redirected) against a scratch
copy of the real directory:

| Scenario | Round 2 | Round 3 |
| --- | --- | --- |
| unmodified (passing control) | 0 failures | **0 failures** ✅ |
| **README deleted** | 0 failures ❌ | **1 failure** ✅ |
| **README overwritten with garbage** | 0 failures ❌ | **1 failure** ✅ |
| **stray `.txt` added** | 0 failures ❌ | **1 failure** ✅ |
| **nested `nested/x.json` added** | 0 failures ❌ | **1 failure** ✅ |
| one-byte JSON edit | 1 failure | 1 failure ✅ |
| JSON deleted | 1 failure | 1 failure ✅ |
| stray `.json` added | 1 failure | 1 failure ✅ |

All four gaps I named are closed and nothing previously caught regressed. Applied in **both** repos
(identical change), and the pinned README digest is correct and identical in both:
`a85485fc8c4277325d85282435002a6a099674c11acdfa5f109a0b3a76313a1a`. E.1's retirement sentence is now
mechanically defended, which was the whole point — the guard protecting the bytes but not the exit route
was the gap.

### SHOULD-FIX 3 (undocumented boundary — does the comment overclaim?) — **CLOSED, no overclaim**

```
# This job intentionally has no database. Essentia specs must stay Rails-free;
# add a database-backed job instead if a future Essentia gate requires rails_helper.
```

Three statements, checked one by one: "no database" — true (no postgres service, no `DATABASE_URL` on
that job); "must stay Rails-free" — exactly the rule the loop enforces by exiting 1; the third is a
remedy, not a claim about the code. It asserts **no** property the mechanism lacks — specifically it does
not claim specs cannot be silently skipped, which was the round-1 sin. It documents the *why*, which is
what `CLAUDE.md` change discipline asks for. The false round-1 comment stayed deleted.

Precision note, not a finding: the code enforces "files whose text matches the tag pattern must not
contain `rails_helper`," which is narrower than "Essentia specs." The comment states a rule for humans
rather than describing the mechanism's coverage, so it does not overclaim — and that mechanism/rule gap
is the deferred under-inclusion item.

---

## R5, one line

**Yes** — every item is correct and green after the app returns to gem `v0.1.0`: the two integrity specs
are pure `Digest`/`Pathname` and reference no gem API, `dependabot.yml` is bot config, the baseline bytes
are exactly what v0.1.0 produces, and reverting item 12 restores `:essentia` on a `spec_helper`-only file
so discovery, the Rails-free check, the floor and the new basename gate all still resolve.

## Scope creep / runtime change

**None.** Still 8 files per repo, unchanged from round 2 — no new files. The round-3 delta touches only
`.github/workflows/ci.yml` and the two integrity specs. Zero changes under `app/`, `lib/`, `config/`,
`python/`, `exe/`, `db/`, the app's `Gemfile`/`Gemfile.lock`, or any gemspec. `Gemfile:34` still
`branch: "main"`.

Not mine, noted as a positive: item D (every golden basename must appear in a dry-run
`full_description`) closes a real hole the floor could not — a fixture silently losing its example — and
strengthens the oracle beyond a lower bound.

## New finding

| # | Rank | Finding |
| --- | --- | --- |
| 1 | NIT | `Dir.children` includes dotfiles, so a stray `.DS_Store` in the baseline directory fails the suite locally while CI stays green — verified: `1 example, 1 failure`. It is gitignored in the app and not listed at all in the gem's `.gitignore`, so it is untracked-but-present. Minor determinism wrinkle (`CLAUDE.md`: keep tests deterministic); one line fixes it (reject entries starting with `.`, or compare against tracked entries). Fixture directories are rarely opened in Finder, so I would not hold the slice for it. |

**Your pre-verification: all correct.** Quoted array and `--` separator present; explicit `grep_status`
branching present, and `$?` at the top of an `else` branch is indeed grep's status (1 no-match, 2 error);
word boundary present; basename gate present; both dry-run counts asserted; boundary comment present;
integrity spec uses `Dir.children` and pins README. Trees clean. Nothing to correct this round.

Deferred items confirmed still absent and correctly so. No re-tier — the round-3 delta is CI config plus
two test-only files. No ambiguity to escalate.

---

## Evidence

```
$ git -C <app> diff --stat 52141f6..a5f71fd
 .github/workflows/ci.yml               | 45 ++++++++++++++++++++++++++++++-----
 spec/baseline_v0_1_0_integrity_spec.rb |  5 ++--
$ git -C <gem> diff --stat ac8f24b..6c56f29
 spec/baseline_v0_1_0_integrity_spec.rb |  5 ++--
$ git status --porcelain   (both repos)  → empty
$ git diff --name-only a99c397..a5f71fd  → 8 files (unchanged set from round 2)
$ git -C <gem> diff --name-only 5360f8f..6c56f29 → 8 files (unchanged set)
```

Word boundary, pattern `(:essentia\b|essentia:[[:space:]]*true\b)`:
```
MATCH   tagged_spec.rb          (RSpec.describe "goldens", :essentia do)
MATCH   tagged2_spec.rb         (RSpec.describe "x", essentia: true do)
no      mapper_spec.rb          (let(:essentia_mapper) …)     <-- round-2 finding, now excluded
MATCH   spec/integration/essentia_extract_golden_spec.rb
$ while IFS= read -r -d "" p; do grep -Eq "$P" -- "$p" && echo "  $p"; done \
    < <(find spec -type f -name "*_spec.rb" -print0)
  spec/integration/essentia_extract_golden_spec.rb
```

Integrity spec, repo file verbatim against a scratch copy of the real directory:
```
0 unmodified (passing control): 1 example, 0 failures
1 README DELETED:              1 example, 1 failure
2 README GARBAGE:              1 example, 1 failure
3 STRAY .txt:                  1 example, 1 failure
4 NESTED JSON (subdir):        1 example, 1 failure
5 one-byte JSON edit:          1 example, 1 failure
6 JSON deleted:                1 example, 1 failure
7 stray .json:                 1 example, 1 failure
8 gitignored .DS_Store:        1 example, 1 failure      (the new NIT)
```

README digest, both repos, and the pin:
```
$ shasum -a 256 <app>/spec/fixtures/mood_probe/baseline_v0_1_0/README.md
a85485fc8c4277325d85282435002a6a099674c11acdfa5f109a0b3a76313a1a
$ shasum -a 256 <gem>/spec/fixtures/mood_probe/baseline_v0_1_0/README.md
a85485fc8c4277325d85282435002a6a099674c11acdfa5f109a0b3a76313a1a
$ grep -n 'README.md' spec/baseline_v0_1_0_integrity_spec.rb
9:      "README.md" => "a85485fc8c4277325d85282435002a6a099674c11acdfa5f109a0b3a76313a1a",
```

Suites at the round-3 HEADs (gate is zero failures):
```
app: 276 examples, 0 failures
gem:  67 examples, 0 failures
gem integrity spec standalone: 1 example, 0 failures
```

**What I did not do:** did not rebuild the amd64 image (relying on the implementer's re-run of the
hardened body plus your pre-verification) and made no claim about gem CI on GitHub. **No file in either
repo was modified** — all mutation testing was on copies under the session scratchpad.

VERDICT: APPROVE
