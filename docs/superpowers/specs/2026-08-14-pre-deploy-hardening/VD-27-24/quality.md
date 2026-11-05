# CODE QUALITY REVIEW — vibe-doctor — VD-27-24

REPO: /Users/lukeolson/projects/vibe-doctor
BASE_SHA: 5c9dfccda17ccf26af5267d099a391e3b2e882a8 (origin/main)
HEAD_SHA: d3ff0b93bba1ce19b55de090b9efbd609bcd560b
BRANCH: fix/pre-deploy-record-and-clamp-coverage
Actual working content lives in the linked worktree:
`/Users/lukeolson/projects/vibe-doctor/.worktrees/pre-deploy-record-and-clamp-coverage`
(the primary checkout is on an unrelated branch, `docs/essentia-gem-v2-design`; all
verification below was run against the worktree, which is a full checkout of this branch).

Read `/tmp/maestri-reviews/VD-27-24/implementer.md` first — done.

---

## Commit 9445dbd — issue #27 — TIER 3 sanity pass

**VERDICT: APPROVE**

Scope check: `git show --stat` lists 26 files, all `.md`, all status `A` (pure add, no
modifications, no hooks present to rewrite content — see Evidence). No `.rb` or spec files
in this commit. Scope matches the stated "docs only" claim.

**16-file phase-a whole-branch record — byte-for-byte unmodified:** These files were
untracked/uncommitted in the repo prior to this branch (confirmed: they show as pure `A`
adds with no corresponding prior tracked blob, and there is no active pre-commit/commit-msg
hook in `.git/hooks/` that could have rewritten them on the way in — only `.sample` files
present). A pure `git add` + `git commit` cannot alter byte content, so "unmodified" reduces
to "was this a clean add with no hook interference," which I confirmed. I do not have an
external prior copy of this specific 16-file set to hash-diff against (searched `/tmp` and
found none), so this claim rests on the add-only diff status plus absence of hooks, not on
an independent checksum against a second source — noted as the limit of this verification.

**Nine copied audit files — verified by checksum, not eyeball**, against
`/tmp/maestri-reviews/SONANCE-MAIN-AUDIT/`:

```
$ for f in CONTEXT.md implementer.md principal.md quality.md security.md spec.md \
           task-board.md test.md thin-binding-design.md; do
    shasum -a 256 "$SRC/$f" "$DEST/$f"
  done
MATCH   CONTEXT.md              5f5af6e7cdd07551972f38caddd500b791137d1b120b537def80ffea4791577f
MATCH   implementer.md          417b5dae996dbbf657d044c9339de317965bbd9389d31ae97081b1916308c774
MATCH   principal.md            c0139a18ce714af7441bf21d780bec8fa1769c92ada2798419e3ee975492a3a1
MATCH   quality.md              8c3a1ada2eeb09ed547a1befe74df3895530ec950be4d5cf50977aff15563e72
MATCH   security.md             822aa52eaa0aaf9d4ee71f4118b607b504706ee07a692ec41e472be001b2edca
MATCH   spec.md                 6443196fc2a22d4f256426c210f90050ba182bb365acd9af51650328060d6c70
MATCH   task-board.md           3776caac99a128390d4fde64919966a239c1bc968226fd039e0e0a816a877d1b
MATCH   test.md                 24d85c0df483df776215025c011977477bc90239b4e54090350da4560ec51553
MATCH   thin-binding-design.md  67113a8abbf47ebc7285a7428790ef63ad2db252a521f5eb9c90a37a10dc5c5a
```
All 9 match exactly. (Note: several other files present in the `/tmp` source directory —
`app-precompile.txt`, `app-suite.txt`, `gem-suite.txt`, `impl-board.md` — were correctly
NOT copied; the diff contains exactly the nine required files plus a new `README.md`.)

**README.md accuracy** — read directly (`docs/superpowers/specs/2026-08-13-whole-flow-audit/README.md`):
- States "the 2026-08-13 audit" — correct; the audit content is dated 2026-08-13 even
  though the commit persisting it lands 2026-08-14 (`git log` shows both commits at
  `2026-08-14 11:00:56 -0700` / `11:05:19 -0700` — this is the persistence commit date,
  not the audit date, and the README correctly describes the latter).
- Three verdicts stated: "ported with reservations," "plugged into Vibe Doctor correctly,"
  "deployable without separately deploying the gem" — these match the three questions and
  verdicts in the source `quality.md`/`spec.md`/`principal.md` I checksummed above (I
  personally authored the "plugged in correctly" verdict in a prior session of this same
  audit and confirm the README's paraphrase is accurate to it).
- Two milestone links, verified live and resolving correctly:
  ```
  $ gh api repos/Lhosb/vibe-doctor/milestones/1 --jq '.title, .html_url'
  Pre-deploy hardening
  https://github.com/Lhosb/vibe-doctor/milestone/1
  $ gh api repos/Lhosb/sonance/milestones/1 --jq '.title, .html_url'
  Pre-deploy hardening
  https://github.com/Lhosb/sonance/milestone/1
  ```
  Both titled "Pre-deploy hardening," both resolve — links are accurate and working.

No re-tier needed; this stayed within Tier 3 scope (docs-only, no logic to sanity-check
beyond "does the diff match its stated shape").

---

## Commit d3ff0b9 — issue #24 — TIER 2

**VERDICT: APPROVE**

### Issue #24 context (read via `gh issue view 24 --repo Lhosb/vibe-doctor --comments`)

Issue is scoped narrowly: the softmax-clamp spec asserted only one direction per head
(`danceability`/`mood_relaxed` upper-only, `mood_acoustic`/`mood_happy` lower-only), so
either bound could be deleted from the mapper with the full suite staying green. Required
work per the issue: give each softmax head both bounds; "keep the clamp — it costs nothing
and is correct insurance." Two follow-up comments raise a **future** decision (what happens
when the gem's `Sonance::Scalar` sanity-range veto is removed by a planned thin-binding
change) but explicitly do NOT require this issue to implement a runtime range-handling
policy — that is future, sequenced work gated on a separate gem change
(`Lhosb/sonance#15`). The dispatch's "coverage-only constraint" is consistent with the
issue as filed.

### Diff scope

```
$ git show --stat --format='' d3ff0b93bba1ce19b55de090b9efbd609bcd560b
 spec/models/mood_vectors/essentia_mapper_spec.rb | 38 ++++++++++++++++--------
 1 file changed, 25 insertions(+), 13 deletions(-)
```
Single file, spec-only. Matches the coverage-only constraint.

### `essentia_mapper.rb` — CONFIRMED INDEPENDENTLY, zero diff from origin/main

```
$ git diff origin/main d3ff0b93bba1ce19b55de090b9efbd609bcd560b -- \
    app/models/mood_vectors/essentia_mapper.rb
(no output, exit 0)

$ git show origin/main:app/models/mood_vectors/essentia_mapper.rb | shasum -a 256
5bfc8db5b470e6323d4b0093ac6600b4a696c9a0ace2e76f3efaf967392c339a  -
$ git show d3ff0b93bba1ce19b55de090b9efbd609bcd560b:app/models/mood_vectors/essentia_mapper.rb | shasum -a 256
5bfc8db5b470e6323d4b0093ac6600b4a696c9a0ace2e76f3efaf967392c339a  -
```
Identical hashes, derived independently rather than trusting the implementer's claim.
Production clamp behavior is unchanged; only test coverage changed. Correct for a
coverage-only fix.

### Does the spec follow this repo's existing RSpec idiom?

Compared against `spec/services/mood_descriptor_spec.rb` (local `def mood(**attrs)` helper
building a defaults hash and merging overrides) and
`spec/services/itunes_preview_matcher_spec.rb` (`def stub_search(term, country: nil,
results:)` — mixed positional/keyword-with-default helper). Both sibling patterns are
"local test helper method with keyword defaults, merged/overridden per example," which is
exactly the pre-existing `descriptors_with(**overrides)` pattern in this file (not
introduced by this diff — it already existed before this change and is extended, not
replaced). `:aggregate_failures` is also pre-existing local idiom, used one line above the
diff (`"clamps arousal emomusic values outside the native range", :aggregate_failures`) and
in the sibling `essentia_parity_spec.rb` ("executes all 24 frozen-baseline comparisons",
`:aggregate_failures`). The new two-example split (one `:aggregate_failures` example per
direction, asserting all four heads inside it) is consistent with that established idiom,
not an invented style.

### Is `softmax_value:` the right abstraction, or does it hide which head is being driven?

**Argument that it is the right abstraction, not a hiding one:**
1. All four softmax heads share identical clamp semantics — same range (`0.0..1.0`), same
   `clamp` implementation call site in `essentia_mapper.rb`. The bug this issue exists to
   close is specifically "each head only tested in one direction," and the fix's job is to
   assert **all four heads, both directions** — i.e., the test's whole point is that the
   heads are NOT differentiated for this assertion. A parameter that broadcasts one value
   to all four heads is the correct shape for "prove the clamp bites uniformly across every
   softmax head," which is exactly what the two new examples assert (each example still
   individually asserts `result.fetch(:danceability)`, `:mood_acoustic`, `:mood_relaxed`,
   `:mood_happy)` — nothing about which head produced which result is hidden; the fetches
   are per-head and explicit).
2. It does not reduce test resolution versus the pre-existing helper: before this change,
   `descriptors_with(danceability_musicnn: 1.1, mood_acoustic_musicnn: -0.1, ...)` also set
   all four heads in a single call — the difference is only that the old call used four
   *different* literals (which produced the asymmetric, incomplete coverage the issue is
   about) versus the new call using one shared literal per direction. `softmax_value:` is
   arguably a **safer** abstraction than the old spelled-out-per-head kwargs precisely
   because it makes it structurally impossible to accidentally reintroduce the
   one-direction-per-head asymmetry that caused this bug — a future author extending this
   helper cannot silently drop one head's bound the way the original four-separate-kwargs
   call allowed.
3. Minor counter-argument (why one could push back): if a future test needed head-specific
   softmax overrides mixed with a shared baseline, `softmax_value:` composed with
   `**overrides` requires the caller to know that `overrides` wins last (see
   `descriptors.merge!(softmax_value...); descriptors.merge(overrides)` — overrides applied
   after softmax_value, so a caller can still override one head individually if needed).
   This composition is a little implicit but is documented by the plain merge-order reading
   of the four-line method body, and the current two call sites don't need it, so this is
   not a real problem today — flagging only as something to watch if a third test author
   adds a mixed-override softmax case later.

**Conclusion: `softmax_value:` is the right abstraction for this issue's actual bug** (an
undifferentiated four-head-uniform clamp check), and does not hide which head is driven —
each head is still explicitly asserted in the example body. Not a finding.

### CLAUDE.md / architecture rules

- Domain logic in models: N/A to this diff (spec-only, no logic added). The mapper itself
  (unchanged) already correctly lives in `app/models/mood_vectors/`, consistent with
  "domain/business logic in models."
- No new service objects: none introduced. Confirmed via the single-file diff stat above.
- No new abstraction without local need: the one new abstraction is the `softmax_value:`
  keyword param on an existing private test helper, justified by and scoped to closing this
  exact issue (see argument above) — not a speculative or premature abstraction.
- Testing rules ("keep new tests in RSpec style used by this repository"): satisfied, per
  the idiom comparison above.

Fully compliant with `CLAUDE.md` and `.github/instructions/rails-architecture.instructions.md`.

---

## Both — shared checks

### Branch position and trailers

```
$ git rev-list --left-right --count origin/main...d3ff0b93bba1ce19b55de090b9efbd609bcd560b
0	2
```
0 behind, 2 ahead of `origin/main` — confirmed independently.

```
$ git log -1 --format='%B' 9445dbd629794468f367bdd4ffd20a9b835ef8a1 | tail -3
Persist pre-deploy review records

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>

$ git log -1 --format='%B' d3ff0b93bba1ce19b55de090b9efbd609bcd560b | tail -3
Cover both softmax clamp bounds

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```
Both commits carry the trailer.

### Full suite, rubocop, brakeman — re-run myself, in the worktree

```
$ cd .worktrees/pre-deploy-record-and-clamp-coverage
$ bundle exec rspec --format progress
...
Finished in 8.62 seconds (files took 0.90983 seconds to load)
299 examples, 0 failures

$ bin/rubocop
Inspecting 207 files
...............................................................................................................................................................................................................
207 files inspected, no offenses detected

$ bin/brakeman --no-pager
Controllers: 27
Models: 23
Templates: 19
Errors: 0
Security Warnings: 0
No warnings found
```
**Matches the implementer's reported numbers exactly: 299 examples / 0 failures / 0
rubocop offenses / 0 brakeman warnings.** No discrepancy — not a finding.

(Noted, not a finding: Brakeman printed an "Obsolete Ignore Entries" section listing two
hashes from `config/brakeman.ignore`. Confirmed this file was last touched in commit
`0d6ed39` — well before `BASE_SHA` — via `git log -1 --oneline -- config/brakeman.ignore`,
and is untouched by this diff. Pre-existing condition, out of scope for this review.)

### Trailing-whitespace claim — verified, confined to the copied audit doc

```
$ git diff --check origin/main...HEAD
docs/superpowers/specs/2026-08-13-whole-flow-audit/implementer.md:223: trailing whitespace.
docs/superpowers/specs/2026-08-13-whole-flow-audit/implementer.md:224: trailing whitespace.
docs/superpowers/specs/2026-08-13-whole-flow-audit/implementer.md:225: trailing whitespace.
docs/superpowers/specs/2026-08-13-whole-flow-audit/implementer.md:228: trailing whitespace.
docs/superpowers/specs/2026-08-13-whole-flow-audit/implementer.md:229: trailing whitespace.
docs/superpowers/specs/2026-08-13-whole-flow-audit/implementer.md:230: trailing whitespace.
```
Exactly six lines, all inside the one copied `implementer.md` audit record (lines 223-230,
markdown two-trailing-space "hard line break" convention — intentional and pre-existing
markdown syntax, not accidental whitespace debt). **Confirmed zero occurrences in any
`.rb` or `spec/` file** — `git diff --check` covers the entire `origin/main...HEAD` range
and the six hits it reports are the only hits; none carry a `.rb` path.

---

## Findings summary

| # | Commit | Finding | Severity |
|---|---|---|---|
| 1 | 9445dbd | Nine copied audit files verified byte-identical to `/tmp` sources by SHA-256; 16-file whole-branch set verified as pure adds with no hook interference (no independent second source existed to checksum against). | Informational — approve |
| 2 | 9445dbd | README.md verdicts, date framing, and both milestone links all verified accurate and live. | Informational — approve |
| 3 | d3ff0b9 | `essentia_mapper.rb` production file independently confirmed byte-identical to `origin/main` (SHA-256 match). | Informational — approve |
| 4 | d3ff0b9 | `softmax_value:` helper parameter is the correct abstraction for this issue's uniform four-head clamp assertion; does not obscure per-head results (each head still explicitly fetched/asserted). Minor note: composition order with `**overrides` is implicit but undocumented — no current call site needs it. | 🔵 Minor / informational |
| 5 | Both | Branch 0 behind `origin/main`, both commits carry the Copilot co-author trailer. | Confirmed, no finding |
| 6 | Both | Re-run suite: 299 examples/0 failures, rubocop 207 files/0 offenses, brakeman 0 errors/0 warnings — matches implementer's reported numbers exactly. | Confirmed, no finding |
| 7 | Both | `git diff --check` trailing-whitespace: exactly 6 lines, all confined to the copied audit `implementer.md`; zero in Ruby/spec files. | Confirmed, no finding |

No 🔴 Critical or 🟡 Important findings on either commit.

## Overall verdicts

- **Commit 9445dbd (issue #27): APPROVE** (Tier 3, no re-tier needed)
- **Commit d3ff0b9 (issue #24): APPROVE** (Tier 2)
