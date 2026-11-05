# Code Quality Review — ESSENTIA-GEM-V2 Phase A Slice 1, Round 3 (final)

First look from Code Quality (no round-2 quality.md exists in this dir, so no prior findings of
mine to close). A-E and NITs are owned by Security/Spec/Test — not re-verified here; only spot-checked
where they intersect maintainability/scope.

## Q1 — Scope match, debris check

Diffs (`git -C <repo> diff BASE..HEAD --stat`, and round2-HEAD..new-HEAD for the delta) match the
stated infrastructure-only scope: app touches `.github/dependabot.yml`, `.github/workflows/ci.yml`,
one integrity spec, and 5 new fixture files (README + 4 JSON); gem touches `ci.yml` (new file),
`Gemfile.lock` (+1 line, platform metadata), same integrity spec, same fixtures. No application code,
no migrations, no controller/model/job touched. No leftover debug artifacts (`evil`, `orphan`, temp
spec files used in the implementer's manual fault-injection) exist in either tree — confirmed with
`find` for those basenames and `git status --porcelain` (clean). `dependabot.yml`'s new `ignore:
mood_probe` entry is scoped and non-behavioral. No dead code, no stale comments carried over from
earlier rounds — the round-2→round-3 diff is a clean superset replacing the old grep-based one-liners.

## Q2 — Embedded shell script maintainability

**Recommendation: extract to a checked-in script.** The body is now ~50 lines of Bash with a nested
`find -print0`/array loop, dual `grep` gates each doing explicit 3-way status handling, an embedded
single-quoted Ruby heredoc-via-`-e` (itself doing JSON parsing, two abort conditions, and a fixture
diff), all inside a YAML `run: |` block, itself inside a single-quoted `docker run -c '...'` argument.
The quoting is already fragile (`'\''` escapes to smuggle single quotes through the outer quote) and
every future edit risks a quoting mistake that YAML/bash won't catch until CI run time — there is no
lint or test coverage on this script today, and none is possible while it lives as a string embedded
three layers deep. It works and is correct (verified `$?`-after-`if` semantics below), but this is past
the point where "workflow YAML" is the right home for it. Move it to something like
`bin/ci/essentia_gate` (or `script/`), invoke it with `docker run ... vibe-doctor-essentia-goldens
bin/ci/essentia_gate` (mount or bake into the image), and it becomes shellcheck-able, unit-testable in
isolation, and diffable without YAML noise. Not a blocker for this slice (behavior is correct and
tested), but I'd fix it before a 4th round of edits touches this body again.

Spot-verified the specific correctness claim since it's easy to get wrong: `$?` inside the `else`
branch of `if grep ...; then ... else grep_status=$?; ... fi` is in fact the grep exit status (no
intervening command resets it) — confirmed empirically: no-match → 1, missing-file error → 2. Matches
manager's pre-verification.

## Q3 — Duplicated integrity specs across repos

Shape is acceptable given the stated constraint (must not share code across repos — they are
independent release artifacts, one embeds the other as a gem dependency, so a shared support file
would defeat the point of the freeze). Five hardcoded SHA-256 literals per repo, duplicated verbatim
across app and gem, is the simplest structure that satisfies "prove I distributed byte-identical
files" without runtime coupling. The only mild smell is that the two spec files are structurally
identical except for one `require "spec_helper"` line difference (app's has `require "digest"`,
`require "pathname"`, `require "spec_helper"`; gem's is missing those explicit requires and relies on
spec_helper transitively) — worth a look but not a defect; RSpec runs green in both. I would not
introduce a shared gem/library just to DRY 5 constants across repos that are intentionally decoupled —
that reintroduces the coupling the freeze is designed to avoid. Current shape stands.

## Q4 — Consistency with existing patterns

- Integrity spec file naming/placement matches repo convention (`spec/<behavior>_spec.rb`, sibling to
  other top-level specs; both repos already have flat `spec/*.rb` files, not nested).
- `spec/fixtures/mood_probe/baseline_v0_1_0/` mirrors the existing `spec/fixtures/mood_probe/golden/`
  layout (same parent dir, dated/versioned sibling) — consistent with the `generate_goldens.rb`
  convention already in the fixtures tree.
- RSpec idiom: `let`, `Digest::SHA256.file(...).hexdigest`, single `it` block — matches this repo's
  terse-spec style seen elsewhere (checked against existing specs in both repos' `spec/` roots).
  Rubocop is clean on the changed file in both repos (`bin/rubocop`/`bundle exec rubocop`, 201/30 files,
  0 offenses).
- YAML style (2-space indent, `runs-on: ubuntu-latest`, `actions/checkout@v6`, `ruby/setup-ruby@v1`)
  matches the pre-existing jobs in the same `ci.yml` (scan_ruby/scan_js/lint/test). The new `essentia`
  job and gem's new `ci.yml` both follow the same step-naming convention (`Checkout code`, `Set up
  Ruby`, `Run test suite`). No inconsistency found.

## Q5 — Risk to slices 2-5

- The embedded-script maintainability issue (Q2) will compound: slice 2+ likely touches this same
  body again (residuals mention future G1 needing `*.json` glob, F.2 mirror, etc.) — every future
  change re-enters the fragile triple-quoting. Recommend extracting before the next edit, not after.
- Confirmed (implementer + my own read) that text-grep discovery structurally cannot see
  `define_derived_metadata`/shared-example-group metadata — already correctly deferred to slice 5, not
  a new finding, just flagging it's a real structural ceiling on this whole discovery approach, not a
  minor gap.
- No other new risks found for slices 2-5 beyond what's already listed as deferred.

## Evidence

```
$ git -C /Users/lukeolson/projects/vibe-doctor diff a99c3973a..a5f71fd2d --stat   # 8 files, +118/-5
$ git -C /Users/lukeolson/projects/vibe-doctor diff 52141f6..a5f71fd2d --stat     # ci.yml + integrity spec only
$ git -C /Users/lukeolson/projects/gems/mood_probe diff 5360f8f..6c56f29 --stat   # 8 files, +100
$ git -C /Users/lukeolson/projects/gems/mood_probe diff ac8f24b..6c56f29 --stat   # integrity spec only, 3 lines
$ find <app spec tree> -iname "*evil*" -o -iname "*orphan*"                       # no results
$ git -C /Users/lukeolson/projects/vibe-doctor status --porcelain                 # clean
$ bundle exec rspec spec/baseline_v0_1_0_integrity_spec.rb   (app)  # 1 example, 0 failures
$ bundle exec rspec spec/baseline_v0_1_0_integrity_spec.rb   (gem)  # 1 example, 0 failures
$ bundle exec rubocop spec/baseline_v0_1_0_integrity_spec.rb (app)  # 1 file, no offenses
$ bash empirical test of if/else $? semantics                       # no-match=1, missing-file=2
```

Files inspected: `.github/workflows/ci.yml` (both repos), `spec/baseline_v0_1_0_integrity_spec.rb`
(both repos), `spec/fixtures/mood_probe/baseline_v0_1_0/*` (both repos), `.github/dependabot.yml`,
`Gemfile.lock` diff, implementer's report.

## Prior findings

No round-2 quality.md exists in this review directory — this is Code Quality's first pass on this
slice. Nothing of mine to mark CLOSED/NOT CLOSED.

## VERDICT: APPROVE-WITH-CHANGES

Functionally correct, in-scope, no debris, consistent with repo conventions, tests/lint green in both
repos. One non-blocking but should-fix-soon recommendation: extract the essentia CI shell body (Q2)
into a checked-in, lintable script before it grows further across slices 2-5.
