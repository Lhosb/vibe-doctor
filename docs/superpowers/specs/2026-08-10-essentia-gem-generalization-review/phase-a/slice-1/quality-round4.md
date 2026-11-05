# Code Quality Review — ESSENTIA-GEM-V2 Phase A Slice 1, Round 4 (final confirmation)

## My round-3 finding

**"Extract the embedded ~50-line shell body to a checked-in, lintable script"** — **CLOSED.**
Proof: `git -C app diff a5f71fd..710620d --stat` shows `ci.yml` shrank 52 lines, `bin/essentia-ci`
added (72 lines, mode `-rwxr-xr-x`), integrity spec +1/-1 (dot-file exclusion, unrelated to my finding,
covered below). The script is now a standalone, shebang'd, `shellcheck`-clean executable; `ci.yml`'s
`essentia` job runs `shellcheck bin/essentia-ci` before building the image, and the docker step's
command is just `/rails/bin/essentia-ci` instead of an inline `-c '...'` string. Verified locally:
`shellcheck bin/essentia-ci` → exit 0; `bundle exec rspec` 276/0; `bundle exec rubocop` 201 files clean.

## Judging the execution

**Readability/factoring:** Good. Same logic as round 3, but now linear top-to-bottom with `set -euo
pipefail`, a `trap` for the temp discovery file, and no quote-escaping gymnastics. The embedded Ruby
`-e` block is unchanged in complexity but is no longer nested inside a shell string inside a YAML
string inside a docker arg — one layer removed is a real readability win. No leftover debris from the
extraction (no dead code, no duplicate comment blocks — the old inline comment about the Rails-free
invariant is gone from `ci.yml` and correctly preserved, reworded, as a header comment in the script).

**Path/naming:** `bin/essentia-ci` is correct for this repo. Confirmed via `ls bin/`: this app already
puts flat operational commands there (`bin/rubocop`, `bin/brakeman`, `bin/bundler-audit`,
`bin/importmap`, `bin/ci`) alongside Rails' own `bin/rails`, `bin/setup`, etc. — it is already a mixed
Rails+repo-tooling directory, not Rails-executables-only, so this fits existing convention rather than
inventing a new one. A dedicated `script/ci/` would also have been defensible but would be inconsistent
with what's already here; no change requested.

**ShellCheck placement:** Correct and it will actually gate. It's a real job step (`run: shellcheck
bin/essentia-ci`) before the docker build step, in the same job — a non-zero shellcheck exit fails the
step and the job, blocking merge on the same terms as every other CI step here. Confirmed the claimed
regression-catch is genuine: implementer's evidence (`implementer.md` lines 63-64) shows shellcheck
flagging SC2068 on a reintroduced unquoted-array bug, then clean after restoration. Not installed
explicitly in the workflow, but relies on the tool preinstalled on GitHub's `ubuntu-latest` runner,
which is standard practice and consistent with how `brakeman`/`bundler-audit` are invoked bare in the
same file.

**Commit message:** Meets the bar. Single commit, message states what changed and *why*: "Keep the
Essentia gate in bin/essentia-ci so ShellCheck and direct tests can catch Bash defects that nested
YAML, Docker, and quoted shell strings hid across three review rounds." That's the CLAUDE.md-style
justification for a new pattern — it's in the commit, not just the review thread.

## The entrypoint discrepancy (manager-flagged, unruled)

**It does not matter — evidence is behaviorally valid as shipped, no redo needed.** I tested both
invocation forms directly on the host (functionally equivalent to the container question: does execing
the file directly vs. `bash <path>` change behavior):

```
$ ./bin/essentia-ci        # direct exec, relies on shebang + mode bit — implementer's proven form
exit=0, 5 examples, 0 failures
$ bash bin/essentia-ci     # shipped form: --entrypoint bash ... /rails/bin/essentia-ci
exit=0, 5 examples, 0 failures
$ diff <both outputs>      # identical except wall-clock timing text
```

`set -euo pipefail` and all logic run identically under both invocations since the script has no
dependency on `$0`, `argv`, or being invoked as its own process. The Dockerfile's `COPY . .` (no
`--chmod`) preserves the build-context file mode, so the exec bit does survive into the image — but
the shipped form doesn't even need that guarantee, since `bash <path>` never checks the exec bit. The
shipped form is strictly *more* robust than the proven one, not less, so there's no gap to close. This
is a case where the two invocations are provably equivalent by inspection of the script, not one where
divergent evidence should be trusted at face value — I re-derived it independently rather than taking
the "should be identical" claim on faith.

## Round-4-only additions (SHOULD-FIX 2, NIT 3) — sanity-checked, not owned by me

- Fixture-binding regex now uses `\b#{Regexp.escape(fixture)}\b` (`bin/essentia-ci`, Ruby block) —
  present, matches Test's round-3 finding.
- Both integrity specs now `reject { |name| name.start_with?(".") }` before comparing directory
  listings (app + gem, confirmed via diff), and gem's `.gitignore` gained `/.DS_Store` to match app's
  existing entry. Consistent, minimal, no scope creep.

## Evidence

```
$ git -C /Users/lukeolson/projects/vibe-doctor diff a5f71fd..710620d --stat
 .github/workflows/ci.yml               | 52 ++----------------------
 bin/essentia-ci                        | 72 ++++++++++++++++++++++++++++++++
 spec/baseline_v0_1_0_integrity_spec.rb |  2 +-
$ shellcheck bin/essentia-ci ; echo $?          # 0
$ ./bin/essentia-ci ; bash bin/essentia-ci      # both exit 0, 5 examples/0 failures
$ bundle exec rspec                             # 276 examples, 0 failures
$ bundle exec rubocop                           # 201 files, no offenses
$ git -C /Users/lukeolson/projects/gems/mood_probe diff 6c56f29..55d85fb --stat
 .gitignore                             | 1 +
 spec/baseline_v0_1_0_integrity_spec.rb | 2 +-
$ git log -1 --format=%B 710620d                # justification present
```

Files inspected: `bin/essentia-ci`, `.github/workflows/ci.yml` (app), both integrity specs, gem
`.gitignore`, commit message, `implementer.md` round-4 evidence.

## Overall slice-1 quality verdict (whole diff, all 4 rounds)

The final state is well-factored: infrastructure-only, Rails-free boundary documented, discovery logic
correct and now testable/lintable in isolation, integrity specs symmetric and appropriately duplicated
across intentionally-decoupled repos, naming/placement consistent with existing conventions in both
repos. My round-3 concern is fully resolved and the extraction was executed cleanly with no new debt.

## VERDICT: APPROVE
