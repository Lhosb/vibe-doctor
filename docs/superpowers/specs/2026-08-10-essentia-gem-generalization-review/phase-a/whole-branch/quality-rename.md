VERDICT: APPROVE-WITH-FINDINGS

BLOCK THE TAG: **NO** — the one finding below is a real, reproducible bug, but it is confined to a
non-CI-exercised local/manual code path (explained below) and does not corrupt the frozen artifact,
the golden values, or anything CI actually verified. I recommend fixing it in a follow-up commit
before the tag if that is cheap (it is a 4-line change plus widening one existing regex-based guard),
but I would not withhold the tag for it alone. Everything else in the 87-file rename is clean.

# 0.3.0 pre-tag review — Code Quality

Repo: `/Users/lukeolson/projects/gems/mood_probe`. Range:
`bb86f29d66ad7b4ae1e0a147b9786f02f010a9d5..77003c5f1796c42fda7807123a56a13c56e71ffe`
(4 commits: `5a539c1` ids, `5b919b2` rename, `80a7dd0` version/changelog, `77003c5` CI fix).

## FINDING — MUST-FIX: stale unqualified descriptor ids in `spec/integration/essentia_golden_spec.rb`

**File/line:** `spec/integration/essentia_golden_spec.rb:20-29` (the `descriptors` `let` block).

**What's wrong:** This is the *only* remaining literal descriptor-id list in the entire repository
still using the pre-0.3.0 unqualified ids:

```ruby
let(:descriptors) do
  %i[
    valence_emomusic
    arousal_emomusic
    danceability        # should be danceability_musicnn
    mood_acoustic        # should be mood_acoustic_musicnn
    mood_relaxed          # should be mood_relaxed_musicnn
    mood_happy            # should be mood_happy_musicnn
  ]
end
```

I grepped every `%i[...]` descriptor literal in the repo (`generate_goldens.rb`,
`capture_essentia_outputs.rb`, `python_seam_spec.rb`, `python_plan_executor_spec.rb`,
`extractor_v2_spec.rb`, `fixtures/sonance/plans/generate.rb`, etc.) — all of them were correctly
updated to the qualified ids in commit `5a539c1`. This one file's `descriptors` list was missed. Note
that the *same file*'s own `public_values` helper (lines 131-140) already correctly uses
`actual.fetch(:danceability_musicnn)` etc. — so the rename was applied inconsistently within one file,
which is worse than a uniformly-missed rename because it looks deliberate at a glance.

**This is exactly the same class of bug commit `77003c5` just fixed** in
`script/capture_essentia_outputs.rb` (old ids there broke the `essentia_golden` CI job on the previous
commit) — but the regression test added alongside that fix
(`spec/release_ci_spec.rb`, "keeps every capture-script descriptor registered") only regexes
`capture_source` (`script/capture_essentia_outputs.rb`). It does not check the sibling literal in
`essentia_golden_spec.rb`, even though `release_ci_spec.rb` already reads that file's source into
`golden_spec_source` for an unrelated assertion (the non-vacuity-floor check). The new guard has a
blind spot for the second copy of the same list.

**Concrete failure scenario, reproduced:**

```
$ bundle exec ruby -Ilib -e '
require "sonance"
Sonance::Registry.default.fetch(:danceability)
'
Sonance::ConfigurationError: unknown descriptor: danceability; valid descriptors: valence_emomusic,
arousal_emomusic, danceability_musicnn, mood_acoustic_musicnn, mood_relaxed_musicnn,
mood_happy_musicnn, embedding_musicnn, bpm_rhythm2013, beat_confidence_rhythm2013
```

`descriptors` is passed straight into `extractor.analyze(...)` / `extractor.analyze_all(...)` in
`actual_values` (line ~146) and in the undecodable-fixture test (line ~88), both inside an
`unless actual_root` / `if actual_root` branch. **Why CI is still green:** the `essentia_golden` job
in `.github/workflows/ci.yml` always runs `script/capture_essentia_outputs.rb` first (the file that
*was* fixed) to populate `SONANCE_ACTUAL_ROOT=/actual`, and with `actual_root` set,
`essentia_golden_spec.rb` reads pre-captured JSON files instead of calling the extractor — so the
stale `descriptors` list is dead code in CI's exact invocation shape. It is *not* dead in the workflow
the file's own top-of-file comment and the README's "Real Essentia verification" section document:
running this spec directly against a live Essentia install without setting `SONANCE_ACTUAL_ROOT` (the
natural thing to do testing on real native-arm64 hardware locally, which the file's header comments
about M1 evidence anticipate). That path would raise `ConfigurationError` instead of running the
intended comparison.

**Severity:** MUST-FIX as a correctness/consistency matter, but I am not blocking the tag on it,
because: the frozen artifact (golden values, CI-verified path) is unaffected; the fix is small,
mechanical, and identical in kind to the one just made in this same range; and it does not touch
anything that becomes harder to fix after the tag (it's pure test code, not a public API or a golden
byte). If you'd rather not re-open the branch, this is a fine one-line-diff fast-follow. I would
recommend also widening `release_ci_spec.rb`'s guard to scan `golden_spec_source`'s `descriptors`
block the same way it scans `capture_source`'s, so this exact class of drift can't recur a third time.

## Q1 — Is the rename complete and consistent?

Yes, apart from the one finding above. I checked systematically, not just spot-checked:

- **Module/class namespace:** zero remaining `MoodProbe`/`mood_probe` module references anywhere in
  `lib/`, `spec/`, `python/`, `exe/`, `script/`. Confirmed by grep.
- **Env var prefix:** every environment variable in the diff is `SONANCE_*`
  (`SONANCE_MODELS_DIR`, `SONANCE_PYTHON`, `SONANCE_FIXTURE_ROOT`, `SONANCE_ACTUAL_ROOT`,
  `SONANCE_ALLOW_NON_CANONICAL`, `SONANCE_IMPORT_SENTINEL`, `SONANCE_FAKE_TRACE`,
  `SONANCE_RESAMPLING_MEASUREMENT`) — no mixed prefix anywhere.
- **Executable:** `exe/mood-probe` → `exe/sonance` is a clean git rename (confirmed `git diff --stat
  -M`), content inside references `require "sonance"`, `Sonance::Registry`, correct banner text.
- **Python executor:** `python/mood_probe_extract.py` → `python/sonance_extract.py`, internal error
  messages ("sonance plan invalid", "sonance configuration failed", "sonance backend crashed") match.
- **Gemspec:** `sonance.gemspec` — name, version constant path (`lib/sonance/version`), homepage,
  executables list, `spec.files` glob all consistent. (The homepage points at a GitHub repo path that
  doesn't exist until the follow-up repo rename — called out as known/accepted, not re-flagged.)
- **Dockerfile.essentia:** `WORKDIR /sonance`, matches `ci.yml`'s `-v "$PWD/tmp:/sonance/tmp"` mount.
- **CI workflow:** every image tag (`sonance-essentia`), path (`spec/fixtures/sonance/...`), and
  executable invocation (`exe/sonance`) in `.github/workflows/ci.yml` is consistently renamed.
- **Fixture directories:** `spec/fixtures/mood_probe/` → `spec/fixtures/sonance/` fully vacated;
  confirmed `ls spec/fixtures/` shows only `sonance/`.

One cosmetic NIT in `README.md`'s opening paragraph: the line
`files required by the requested descriptors, and \`[:bpm_rhythm2013]\` requires no model` is 86
characters, while every other line in that same paragraph is hand-wrapped to 73-77 characters. The
longer qualified id (`bpm_rhythm2013` vs. the old `bpm`) was substituted in place without re-flowing
the paragraph. Purely cosmetic, not worth blocking on, but it's a small tell of a mechanical
find-and-replace and would look better rewrapped.

## Q2 — Debris

None found beyond the one stale descriptor list above (which is not really "debris" — it's live code,
just unqualified). Specifically checked and confirmed clean:
- No empty directories (`find . -type d -empty` outside `.git`: no hits).
- No orphaned `mood_probe`-named files or directories (`spec/fixtures/mood_probe/`, `lib/mood_probe/`,
  `lib/mood_probe.rb` all gone via clean git delete/rename, not left behind).
- No stray bytecode/generated artifacts tracked (`python/__pycache__`,
  `spec/support/fake_essentia/essentia/__pycache__`, `spec/support/import_tripwire/essentia/__pycache__`
  exist on disk from local test runs but are gitignored and untracked — confirmed with
  `git ls-files` returning nothing for those paths).
- The three remaining textual `mood_probe`/`MoodProbe` mentions in the tree
  (`spec/fixtures/sonance/baseline_v0_1_0/PROVENANCE.md`,
  `spec/fixtures/sonance/baseline_v0_1_0/README.md`, `spec/fixtures/sonance/golden/PROVENANCE.md`) are
  all correct, intentional historical references to the frozen `v0.1.0` tag's original name (a
  permanent historical fact, not a stale reference to update) — this matches the dispatch's
  "known and accepted" list.
- Every other apparent "leftover" I found on a broad grep (`mood_happy-msd-musicnn-1.pb` filenames,
  baseline JSON keys, `fake_essentia` test-double filename checks) is a **model filename or
  frozen-baseline app-column-name reference**, not a descriptor id — those are correctly untouched by
  design (model filenames are upstream-fixed; the frozen baseline is keyed by app column names per the
  dispatch's explicit ruling).

## Q3 — Commit hygiene: was commit A (`5a539c1`) truly isolable?

Yes, verified, not just asserted. I checked out `5a539c1` alone (stashed nothing, tree was already
clean) and ran the full suite in isolation: **191 examples, 0 failures; rubocop 48 files, no
offenses** — entirely on the `mood_probe` namespace, before any rename. `git show 5a539c1 --stat`
touches only descriptor-id-bearing files (registry, specs, fixtures, plan generator) — zero namespace
files. The commit message is unusually strong evidence for a rename-adjacent change: it embeds the
exact before/after ordered-value-list command and output proving the golden JSON values are
byte-identical apart from key renames, plus a SHA-256 match and a `cmp` result. This is precisely the
kind of self-contained, independently-reviewable commit the Principal's separation requirement asked
for, and it delivers on it. Returned to `77003c5` afterward; tree confirmed clean before and after.

## Q4 — Duplicate-id validation in `Registry#initialize`

Well-placed and idiomatic. `validate_unique_ids!(models, :model)` /
`validate_unique_ids!(descriptors, :descriptor)` are called first in `initialize`, before any
freezing — correct fail-fast ordering. The implementation:

```ruby
def validate_unique_ids!(records, type)
  duplicate_id = records.map(&:id).tally.find { |_id, count| count > 1 }&.first
  raise ArgumentError, "duplicate #{type} id: #{duplicate_id}" if duplicate_id
end
```

is a clean, idiomatic `Enumerable#tally` use, and `ArgumentError` matches every other
constructor-time validation already in this file (`Model`'s filename/URL/digest checks all raise
`ArgumentError`, reserving `ConfigurationError` for runtime lookups like `#fetch` — a split I already
verified is deliberate and consistent in the 0.2.1 round). One small additional correctness
improvement is bundled cleanly into the same hunk: `@models_by_id`/`@descriptors_by_id` are now built
from the frozen `@models`/`@descriptors` instead of the raw constructor arguments — strictly more
correct, directly related to the code already being touched, not scope creep. Both duplicate-id paths
have real, well-named specs (`registry_spec.rb:14-26`) asserting the exact error class and message.

## Q5 — `CHANGELOG.md`

Useful and well-structured for a reader upgrading across the break: leads with an explicit
"This is a breaking release" statement, a full before/after id table (including the two ids that did
*not* change, `valence_emomusic`/`arousal_emomusic`, which is a good inclusion — it answers the
question "did these change too?" instead of leaving it ambiguous by omission), an explicit "no aliases
are provided" statement, and a pointer to the `v0.1.0`/`v0.2.0` tags as the compatibility path. This
matches the Principal's ruling document I read. Minor NIT: no release date on the `## 0.3.0` heading
(common in Keep-a-Changelog-style files); not worth blocking on for a first CHANGELOG entry with no
established convention to violate.

## EVIDENCE

```
$ git -C .../mood_probe status --porcelain            # empty, start to finish
$ git -C .../mood_probe log --oneline bb86f29..77003c5
77003c5 fix: qualify release capture descriptors
80a7dd0 chore(release): prepare sonance 0.3.0
5b919b2 refactor!: rename MoodProbe to Sonance
5a539c1 feat: qualify descriptor identifiers

$ git diff bb86f29..77003c5 --stat            # 87 files changed, 649 insertions(+), 556 deletions(-)
$ git diff bb86f29..77003c5 --diff-filter=D --name-only
lib/mood_probe.rb
lib/mood_probe/version.rb
spec/fixtures/mood_probe/golden/{chirp,clicks,sine_440,white_noise}.json   # content-changed too much for -M to detect as rename; values proven identical in commit A's message

$ grep -riIl "mood.probe\|moodprobe" . --include="*" | grep -v .git
./spec/fixtures/sonance/baseline_v0_1_0/PROVENANCE.md    # historical, correct
./spec/fixtures/sonance/baseline_v0_1_0/README.md         # historical, correct
./spec/fixtures/sonance/golden/PROVENANCE.md              # historical, correct
./tmp/baseline-parity.json                                # untracked local scratch, not in repo

$ grep -rnE '\b(danceability|mood_acoustic|mood_relaxed|mood_happy)\b' <all source types>
# only non-id hits (model filenames, baseline JSON keys, fake_essentia filename checks)
# PLUS spec/integration/essentia_golden_spec.rb:24-27 (the finding above)

$ bundle exec ruby -Ilib -e 'require "sonance"; Sonance::Registry.default.fetch(:danceability)'
Sonance::ConfigurationError: unknown descriptor: danceability; valid descriptors: ...
# reproduces the finding directly against the live registry

$ git checkout -q 5a539c1 && bundle exec rspec && bundle exec rubocop
191 examples, 0 failures
48 files inspected, no offenses detected
$ git checkout -q 77003c5   # back to HEAD; git status --porcelain empty before and after

$ find . -type d -empty -not -path "./.git/*"    # no output
$ git ls-files python/__pycache__/ spec/support/*/essentia/__pycache__/   # no output (untracked)
```

I also independently re-ran the full suite at final HEAD (`77003c5`) myself, not just the manager's
pre-verified baseline:

```
$ bundle exec rspec
192 examples, 0 failures
$ bundle exec rubocop
48 files inspected, no offenses detected
$ git status --porcelain     # empty
```

VERIFIED matches the manager's baseline exactly. No repository file was left modified; only this
report was written.
