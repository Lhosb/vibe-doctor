# CODE QUALITY REVIEW — sonance #17 and #19 — final Tier 2 gate

**VERDICT: APPROVE.** All findings below are non-blocking/cosmetic. Nothing here should
hold up the push.

REPO: /Users/lukeolson/projects/gems/mood_probe
BASE_SHA: d514137a09facf8c64519e189aed57c3abaf5635
HEAD_SHA: 11a1bafdb629b1fa8bfbc9349170d335e5c5fcca
BRANCH: fix/pin-python-stack-and-notice-uris

Working content lives in the linked worktree:
`/Users/lukeolson/projects/gems/mood_probe/.worktrees/pin-python-stack-and-notice-uris`
(the primary checkout stays on `main`, untouched). All commands below ran there.

Per the dispatch, I did NOT relitigate the already-settled items (build reproducibility,
mutation battery, the OCI-index digest, the six NOTICE/licence URL 200s, the
recorded-not-pinned python3 decision). Scope below is quality/idiom only, as assigned.

---

## Diff shape

```
$ git log --oneline d514137a09facf8c64519e189aed57c3abaf5635..11a1bafdb629b1fa8bfbc9349170d335e5c5fcca
11a1baf Close spec gaps F1/F2/F3/F5/F6 on canonical environment guard (issue #17 test review)
c119c14 Correct python3 version record and Dockerfile digest comment (issue #17 follow-up)
965503d Pin numpy, base image digest, and Python version for reproducible Essentia builds (issue #17)
084399b Add licence URIs and per-model source URLs to NOTICE (issue #19)

$ git diff --stat d514137a09facf8c64519e189aed57c3abaf5635 11a1bafdb629b1fa8bfbc9349170d335e5c5fcca
 Dockerfile.essentia                             | 15 +++--
 NOTICE                                           | 26 ++++++++
 constraints.txt                                  | 35 +++++++++++
 spec/canonical_essentia_environment_spec.rb     | 85 ++++++++++++++++++++++++--
 spec/support/canonical_essentia_environment.rb  | 26 +++++++-
 5 files changed, 176 insertions(+), 11 deletions(-)
```

---

## 1. Does `constraints.txt` read clearly to someone encountering it cold?

**Yes.** Read the full file (reproduced in relevant part below). It is structured in four
clearly-labeled blocks: why numpy is pinned at all (ties to issues #9/#16/#17 and explains
the *consequence* of not pinning — "a bit-identity gate on an unpinned numpy will go red for
environment drift"), **HOW IT WAS DETERMINED** (exact base image, exact venv/pip command,
exact measured result, and an explicit `Date measured: 2026-08-14`), a **RECORDED BUT NOT
PINNED** block for python3 with the precise interpreter version and its verification source
(`packages.debian.org/trixie/python3.13`), a **WHY PYTHON3 IS NOT APT-PINNED** rationale
block, and a closing **"To update numpy:"** paragraph that gives the exact re-measurement
command plus the two other places that must move in lockstep
(`CANONICAL_NUMPY_VERSION` in `spec/support/canonical_essentia_environment.rb`, and golden
fixtures). This directly answers both halves of the question: HOW to re-measure (the exact
`pip install` + `python3 -c` command is given verbatim) and WHEN (the date-stamped
measurement plus the drift-detection rationale make it clear re-measurement is needed any
time the base image, the essentia-tensorflow pin, or the golden fixtures move). Nothing
here required inference — it's copy-pasteable.

Minor, non-blocking observation: the file mixes a code-style pinning line (`numpy==2.5.2`)
with a comment block nearly 4x its length. That's the right trade for a file whose entire
job is to prevent silent drift — the comment IS the artifact's value — so I'm not
recommending trimming it.

## 2. Do the new specs in `spec/canonical_essentia_environment_spec.rb` follow this repo's existing RSpec idiom?

Compared against sibling specs in the same `spec/` directory (`license_notice_spec.rb`,
`registry_spec.rb`, `result_spec.rb`, `errors_spec.rb`) rather than inventing a house style:

- **Requiring supporting libs at top, then a top-level `RSpec.describe` string, not a
  described_class symbol** — matches `license_notice_spec.rb`'s
  `RSpec.describe "model fetch license notice" do`; this spec uses
  `RSpec.describe "canonical Essentia golden environment" do`, same shape.
- **Frozen string constants used as fixed inputs at the top of the file** —
  `license_notice_spec.rb` uses `let(:root)`, `let(:executable)` etc. (RSpec `let`), while
  this spec uses plain top-level frozen constants (`CANONICAL_CPU`, `PINNED_NUMPY`). Both
  idioms are present elsewhere in this repo: `result_spec.rb` and `value_spec.rb` (not
  quoted here for length, but checked) use top-level constants for fixed sample data in
  several places rather than `let`, so this is an existing, not invented, pattern — the
  choice tracks whether the value needs lazy/per-example evaluation (it doesn't here: CPU
  string and numpy version are pure literals).
- **The `# F1:`, `# F2:`, `# F3:` comments tagging each block to a specific test-reviewer
  finding ID** — this is new *content* but not a new *idiom*: it's a plain Ruby comment
  above the block it documents, same mechanical shape as the provenance-style comments
  already used throughout `constraints.txt` and `Dockerfile.essentia` in this same branch,
  and consistent with this codebase's general habit (seen across `lib/sonance/registry.rb`,
  `lib/sonance/value.rb`) of leaving a short rationale comment directly above the code that
  needs it, rather than a changelog-only note. Not an invented style.
- **`Open3.capture3` for subprocess assertions** (the "prevents the golden generator from
  writing on arm64" example) matches `license_notice_spec.rb`'s use of `Open3.capture3` for
  exercising the real `exe/sonance` CLI subprocess — same tool, same pattern (stub the
  environment via a `-e` inline script / `RUBYOPT`, assert on `status`/`stdout`/`stderr`).
- **`described_class`/module-method call style**: `CanonicalEssentiaEnvironment.verify!(...)`
  called directly (module function, not an instance) matches the module's own definition
  style (`module CanonicalEssentiaEnvironment; def self.verify!(...); end; end`) — the spec
  doesn't invent an instantiation pattern the module doesn't support.

No idiom mismatches found. The one thing I'd flag as worth a second look (not a blocker,
not new to this branch): the `PINNED_NUMPY = "2.5.2".freeze` top-level constant duplicates
the literal already in `CANONICAL_NUMPY_VERSION` and in `constraints.txt`, but the file
comment directly above it explains why on purpose — `# F1: use a literal, not the constant
under test — a constant-derived control moves with the bound` — this is a deliberate,
documented test-independence choice (closing exactly the F1 finding named in the commit
message), not an accidental duplication. Correct call, well-explained in-line.

## 3. Is `CANONICAL_NUMPY_VERSION` in the right place?

**Yes — `spec/support/canonical_essentia_environment.rb` is the correct home, not `lib/`.**
Checked the repo layout:

```
$ find lib -name '*.rb'
lib/sonance.rb
lib/sonance/backends/essentia_python.rb
lib/sonance/errors.rb
lib/sonance/extractor.rb
lib/sonance/model_store.rb
lib/sonance/plan.rb
lib/sonance/registry.rb
lib/sonance/result.rb
lib/sonance/value.rb
lib/sonance/version.rb

$ find spec/support -maxdepth 1 -type f
spec/support/recording_cli_analyze.rb
spec/support/canonical_essentia_environment.rb
spec/support/recording_model_fetch.rb
```
`CanonicalEssentiaEnvironment` is exclusively a build/test-reproducibility gate: it is
`require_relative`'d only from `spec/canonical_essentia_environment_spec.rb` and from
`spec/fixtures/sonance/generate_goldens.rb` (the golden-regeneration script) — never from
anything under `lib/`. It has no role in the shipped gem's runtime behavior (nothing in
`Sonance::Extractor`, `Sonance::Registry`, or the public API references it). It sits
alongside two other test-only support modules that follow the identical shape
(`recording_cli_analyze.rb`, `recording_model_fetch.rb` — both are plain Ruby modules with
test-scoped helper state, required only from specs). Placing a numpy-version constant that
exists purely to gate golden-fixture regeneration inside `lib/` would incorrectly imply
it's part of the shipped gem's public surface; `spec/support/` is exactly where this
codebase already puts this category of thing.

## 4. `Dockerfile.essentia` readability — digest comment and `--constraint` wiring

```dockerfile
# syntax=docker/dockerfile:1

# The digest below is the multi-arch OCI index (application/vnd.oci.image.index.v1+json),
# not the amd64 child manifest. Both linux/amd64 and linux/arm64 are present in the index.
# Do not replace it with the platform-specific child digest — that breaks arm64 builds.
FROM ruby@sha256:939bb2710ba0a49ffdba9470b4e562c9dfc5ee6718ba5a5214f1d421d0414d29
...
COPY constraints.txt .
RUN python3 -m venv /usr/local/essentia-venv && \
    /usr/local/essentia-venv/bin/pip install --no-cache-dir \
        --constraint /sonance/constraints.txt \
        "essentia-tensorflow==2.1b6.dev1389"
```
Yes, the next person would understand it. The comment states the concrete media type
(`application/vnd.oci.image.index.v1+json`) rather than just asserting "it's multi-arch," so
a future engineer who runs `docker manifest inspect` or `crane manifest` and sees an index
type will recognize the match instead of wondering if the comment is stale. It also states
the concrete consequence of getting this wrong ("breaks arm64 builds") rather than a vague
"don't change this," which is the actionable form of a guard comment. The `--constraint`
wiring is legible in isolation too: `COPY constraints.txt .` happens before the `pip
install`, and the `--constraint` flag points at the exact path just copied
(`/sonance/constraints.txt`, matching `WORKDIR /sonance`) — a reader doesn't have to
cross-reference anything to see that the constraint file is actually wired into the install
it's meant to pin. No readability finding.

## 5. Is the gem's NOTICE well-organised after 084399b, or has it become a wall?

```
$ git diff --stat d514137a09facf8c64519e189aed57c3abaf5635 11a1bafdb629b1fa8bfbc9349170d335e5c5fcca -- NOTICE
 NOTICE | 26 ++++++++
$ wc -l <(git show d514137a09facf8c64519e189aed57c3abaf5635:NOTICE)   # 16 lines before
$ wc -l <(git show 11a1bafdb629b1fa8bfbc9349170d335e5c5fcca:NOTICE)   # 42 lines after
```
16 → 42 lines (roughly 2.6x), but **not a wall** — the added content is a single flat,
scannable list, not new prose. Structure after the change, read directly:
1. MIT (implicit, one-line header)
2. AGPL/Essentia paragraph, immediately followed by one indented licence-URL line
3. CC BY-NC-ND/models paragraph, immediately followed by one indented licence-URL line
4. A new "Source URLs for the six model files" section: one `Models base URL:` line, then
   six two-line entries (`filename` / indented URL) — mechanically uniform, easy to skim or
   `grep`
5. Closing one-paragraph disclaimer, unchanged

Every new line is either a licence URL or a `filename` + `URL` pair — there is no new
narrative prose competing for the reader's attention, and the two license URLs sit directly
under the paragraph that names that license, so a reader never has to jump around to find
"which URL goes with which license." This is comparable in method to (and, read side by
side, notably terser than) vibe-doctor's `NOTICE` on `fix/model-attribution-notice`
(`origin/main` in vibe-doctor does not yet contain this file — checked directly with `git
show origin/main:NOTICE`, which errors with "path 'NOTICE' does not exist in 'origin/main'";
the file exists on the pushed-but-unmerged `fix/model-attribution-notice` branch instead,
which is what I compared against). Vibe-doctor's version additionally carries an
issue-#23-contingent caveat paragraph and an "Essentia is invoked as a separate subprocess…
this is an architectural fact, not a legal opinion" paragraph that this gem's NOTICE has no
equivalent need for (the gem doesn't vendor model binaries the way the app currently does).
Read side by side, the gem's NOTICE remains the terser, easier-to-scan document of the two,
and did not need to adopt the app's longer form. Not a finding.

One pre-existing regression-guard is worth naming, not as a new finding but as confirming
coverage held: `spec/license_notice_spec.rb`'s `"states the compliance floor without the
obsolete per-model claim"` example asserts the NOTICE still contains `"Sonance::Registry"`,
`"CC BY-NC-ND 4.0"`, `"ShareAlike"`, `"NoDerivatives"` and does NOT contain `"depending on
the model"` — this ran green in the 199-example run below, so the added URL block did not
disturb the existing compliance-floor language it sits inside.

## 6. CLAUDE.md conventions

**No `CLAUDE.md` exists in this repository** — checked at the worktree root and one level
down; only `.github/workflows/ci.yml` is present under `.github/`, no
`copilot-instructions.md` or equivalent either:
```
$ find . -maxdepth 1 -iname "CLAUDE*"; find .github -type f
.github/workflows/ci.yml
```
This is a plain Ruby gem (no Rails, no `app/`, no `app/services`), so the Rails-specific
architecture rules in vibe-doctor's `CLAUDE.md` (models vs. services vs. controllers vs.
jobs) have no applicable surface here. The general principles that DO transfer — small
public APIs, DRY applied pragmatically rather than speculatively, explicit failure
semantics, comments that explain *why* rather than *what* — are all satisfied by this diff:
no new class or public API was introduced (only a private constant, a private helper
tightened for testability, and comment/documentation content); the one behavioral change
(`--constraint` wiring in the Dockerfile) is minimal and directly tied to the stated
problem (numpy drift); and every non-obvious decision (why python3 isn't apt-pinned, why the
digest must stay an index, why `PINNED_NUMPY` is a literal not a constant reference) is
explained in-line at the point a future reader would question it. No convention violation.

---

## Suite — run once, not the mutation battery

```
$ cd .worktrees/pin-python-stack-and-notice-uris
$ bundle exec rspec --format progress
Run options: exclude {essentia: true}

Randomized with seed 59844
.......................................................................................................................................................................................................

Finished in 3.76 seconds (files took 0.10352 seconds to load)
199 examples, 0 failures

$ bundle exec rubocop
Inspecting 49 files
.................................................

49 files inspected, no offenses detected
```
199 examples / 0 failures, matching the Test reviewer's independently-recorded 199/0.
Rubocop: 49 files, no offenses (not explicitly asked for, ran it anyway since it's fast and
free evidence; not a requirement, no findings from it).

---

## Findings summary

| # | Item | Finding | Severity |
|---|---|---|---|
| 1 | `constraints.txt` | Clear derivation instructions, exact re-measurement command, and a dated measurement. Fully answers "how" and "when" to re-measure. | Approve, no finding |
| 2 | `canonical_essentia_environment_spec.rb` | Matches existing sibling-spec idioms (string-described `RSpec.describe`, top-level frozen constants where appropriate, `Open3.capture3` for subprocess assertions, in-line rationale comments). `PINNED_NUMPY` literal duplication is deliberate and documented (F1 fix), not accidental. | Approve, no finding |
| 3 | `CANONICAL_NUMPY_VERSION` placement | Correctly in `spec/support/`, matching this repo's existing test-only-support-module pattern; has no runtime role and no `lib/` code references it. | Approve, no finding |
| 4 | `Dockerfile.essentia` | Digest comment names the concrete OCI media type and the concrete failure mode (arm64 breakage) rather than a vague warning; `--constraint` wiring is directly traceable from `COPY` to `pip install` flag. | Approve, no finding |
| 5 | NOTICE organization | 16→42 lines, but the added content is a uniform, scannable filename/URL list, not prose — not a wall. Compared directly against vibe-doctor's (unmerged, on `fix/model-attribution-notice` — not yet on vibe-doctor `origin/main`) NOTICE; the gem's version remains the terser of the two. Existing compliance-floor regression spec still passes. | 🔵 Minor/cosmetic note only (line-count growth), not a defect |
| 6 | CLAUDE.md | No CLAUDE.md exists in this repo; Rails-specific rules don't apply to a plain gem. General principles (small API surface, explained rationale, no speculative abstraction) are respected. | Approve, no finding |
| 7 | Suite | Re-ran independently: 199 examples/0 failures, rubocop 49 files/0 offenses — matches prior reviewer numbers. | Confirmed, no finding |

No 🔴 Critical or 🟡 Important findings. The one 🔵 item (NOTICE line-count growth) is
explicitly non-blocking per the dispatch's own instruction to not hold a correct change
hostage to style — and on inspection it isn't even a style problem, just a longer file for
a legitimate reason (six new URLs, one line each).

## VERDICT: APPROVE

Both repos left clean and read-only: no edits, no commits, nothing pushed.
```
$ git -C /Users/lukeolson/projects/gems/mood_probe status --short
?? .worktrees/          (pre-existing worktree link entry, not created by this review)
$ git -C /Users/lukeolson/projects/gems/mood_probe/.worktrees/pin-python-stack-and-notice-uris status --short
(clean)
```
