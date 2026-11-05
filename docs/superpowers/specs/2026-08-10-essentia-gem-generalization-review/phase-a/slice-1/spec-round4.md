# ESSENTIA-GEM-V2 Phase A — Slice 1 SPEC REVIEW, ROUND 4 (final confirmation)

**Reviewer:** Plumb (Spec Reviewer, APPROVED round 3) · scope: my own round-3 NIT + the extraction · read-only.
Deltas: app `a5f71fd..710620d` (3 files), gem `6c56f29..55d85fb` (2 files). Both trees clean.

**VERDICT: APPROVE** — the extraction preserves the approved behaviour exactly, my dotfile NIT is closed
without opening a gap, and the entrypoint discrepancy does not matter (proven below, both forms
byte-identical). One factual correction to your pre-verification. No blocking findings.

---

## 1. My round-3 NIT (dotfiles) — **CLOSED, no new gap**

`Dir.children(...).reject { |name| name.start_with?(".") }.sort`, identical in both repos. Repo spec run
verbatim against a scratch copy of the real directory:

```
0 unmodified:            1 example, 0 failures    (passing control)
1 .DS_Store:             1 example, 0 failures    <-- my NIT, closed
2 stray .txt:            1 example, 1 failure
3 stray .json:           1 example, 1 failure
4 stray subdirectory:    1 example, 1 failure
5 README deleted:        1 example, 1 failure
6 README garbage:        1 example, 1 failure
7 one-byte JSON edit:    1 example, 1 failure
8 JSON deleted:          1 example, 1 failure
9 README.md -> .README.md: 1 example, 1 failure   <-- the hiding attempt still fails
```

Every non-dot addition is still rejected and nothing regressed. Case 9 is the one that mattered for "no
new gap": the dot exclusion cannot be used to *hide* a required file, because the key set still demands
`README.md`, so renaming it out of view fails the file-set assertion. The only thing now unobservable is
"an untracked dotfile exists" — exactly what we wanted ignored.

## 2. Does `bin/essentia-ci` preserve exactly the round-3 behaviour? — **YES**

I lifted the approved `-c` body out of `a5f71fd:.github/workflows/ci.yml`, un-escaped the `'\''`
sequences, stripped indentation from both sides, and diffed it against the script. **Three hunks, no
more:**

| Hunk | Change | Status |
| --- | --- | --- |
| line 13 | `done < <(find … -print0)` → `done < "$discovery_file"` | authorized — Security MUST-FIX 1 |
| line 30 | `ruby -rjson -e ` vs `-e '` | **artifact of my own quote-normalisation**, not a difference |
| line 37 | `include?(fixture)` → `/\b#{Regexp.escape(fixture)}\b/` + `match?` | authorized — Test SHOULD-FIX 2 |

Every other line — every gate, guard, error message, ordering and exit path — is identical. Confirmed
independently by presence check, all 15 **PRESENT**: strict mode; tag pattern with `\b`; discovery
`grep_status` guard; non-vacuity via array length; Rails-free rejection; rails-free `grep_status` guard;
independent fixture floor; dry-run `failure_count` zero; dry-run load-errors zero; fixture→example
binding; floor assertion; real-run status captured; final count equality; plus the two new guards
(traversal-must-succeed, anchored binding). Exit paths appear in the approved order:
traversal guard → discovery `grep_status` → non-vacuity → Rails-free → rails-free `grep_status` → floor →
floor assertion → real-run status → final count.

**Nothing dropped, nothing reordered, nothing weakened.** The two deltas both strengthen: the old form
never checked `find`'s status at all, and substring binding would have let `sine_44` satisfy `sine_440`.

Extraction hygiene: mode `100755` in git and on disk; `bin/` is not in `.dockerignore`, so the script
ships and the `COPY --chown=rails:rails --from=build /rails /rails` chain preserves mode and ownership;
`shellcheck bin/essentia-ci` is **clean** locally and `bash -n` parses; the lint step runs *before* the
docker build, so a defect fails fast and cheap; RuboCop still reports 201 files, so the bash file is
correctly not treated as Ruby; and the script is referenced from nowhere but `ci.yml`. The
`# This job intentionally has no database…` comment survived the move intact and still overclaims
nothing.

## 3. The `--entrypoint bash` vs `--entrypoint /rails/bin/essentia-ci` discrepancy — **does not matter; evidence does not need redoing**

The two forms differ in exactly two respects, both benign, and the shipped one is the more robust:
`bash script` ignores the executable bit (so the shipped form *relaxes* a precondition rather than adding
one), and only direct exec consults the shebang — but `#!/usr/bin/env bash` and `--entrypoint bash`
resolve the same binary via `PATH` (the Dockerfile prepends only `/usr/local/essentia-venv/bin`, which
contains no `bash`). `$0`, argv, CWD (`WORKDIR /rails` in both), and `set -euo pipefail` — now inside the
script rather than in the `-c` string — are identical either way.

Demonstrated, not merely argued. Both forms driven down the one deterministic path available outside the
image:

```
$ cd /Users/lukeolson/projects/vibe-doctor/spec
$ bash /…/bin/essentia-ci        → "find: spec: No such file or directory" / "Failed to discover
                                    Essentia spec candidates" · exit=1
$ /…/bin/essentia-ci             → byte-identical output · exit=1
```

The composition risk reduces to "the file is present and readable in the image", which the
`.dockerignore` and `COPY` chain establish by reading. `--entrypoint bash` on this same image is itself
already proven by the rounds 1–3 container runs. **So: not a blocker and no re-do required.** That said,
re-running the shipped command once against the already-built image costs one `docker run` and would
close the proven-vs-shipped gap for free — worth doing if the image is still on the box, but I am not
holding the slice for it.

## 4. Defining property — still satisfied

**Yes.** `bin/essentia-ci` is CI-only: not loaded by Rails, not invoked by the image's `ENTRYPOINT` or
`CMD`, referenced solely by `ci.yml`, and it touches no gem API. It belongs to the I commit alongside the
`ci.yml` that calls it, so J.5 keeps them together — reverting the behaviour commit restores `:essentia`
on a `spec_helper`-only golden spec, and discovery, the Rails-free check, the floor, the basename binding
and the final count all still resolve at gem `v0.1.0`. Both integrity specs remain pure
`Digest`/`Pathname`.

## 5. Scope creep / runtime change

**None.** Exactly one new file per repo, both non-runtime: app `bin/essentia-ci` (net −47 lines of YAML,
+72 of reviewable script), gem `.gitignore`. Still zero changes under `app/`, `lib/`, `config/`,
`python/`, `exe/`, `db/`, the app's `Gemfile`/`Gemfile.lock`, or any gemspec. `Gemfile:34` still
`branch: "main"`. Suites: app **276/0**, RuboCop 201 clean; gem **67/0**, RuboCop 30 clean.

---

## Findings

| # | Rank | Finding |
| --- | --- | --- |
| 1 | NIT | The script relies on the caller's CWD — no `cd` to the app root — so it only works from the repo root. Mitigated by the new traversal guard, which turns that into a clear named error (`Failed to discover Essentia spec candidates`, exit 1) rather than a confusing one, as shown in §3. A `cd "$(dirname "$0")/.."` would make it location-independent now that it is meant to be runnable directly. Optional. |

**Correction to your pre-verification (one item, minor).** ".DS_Store added to the gem .gitignore to
match the app" — it does not match: the app has unanchored `.DS_Store` (matches at any depth, `.gitignore:6`),
the gem has `/.DS_Store` (repo root only, `.gitignore:1`). So a `.DS_Store` under the gem's
`spec/fixtures/…` is still untracked-but-unignored. Zero impact on the gate now that the spec skips
dotfiles, but the claim of parity is inaccurate. Everything else you listed I confirmed: trees clean;
`bin/essentia-ci` present at mode 755; shellcheck clean (I ran it too); the `Lint Essentia CI script` step
precedes the docker build; the docker step invokes `/rails/bin/essentia-ci`; suites and RuboCop as stated.

Deferred items confirmed still absent and correctly so. No re-tier — the round-4 delta is a CI-only
script, a workflow edit, two test-only files and a `.gitignore` line. No ambiguity to escalate.

---

## Evidence

```
$ git -C <app> diff --stat a5f71fd..710620d
 .github/workflows/ci.yml               |  50 +----------
 bin/essentia-ci                        |  72 ++++++++++++++++   (new mode 100755)
 spec/baseline_v0_1_0_integrity_spec.rb |   2 +-
$ git -C <gem> diff --stat 6c56f29..55d85fb
 .gitignore                             |   1 +
 spec/baseline_v0_1_0_integrity_spec.rb |   2 +-
$ git status --porcelain (both)  → empty
$ git diff --name-only a99c397..710620d → 9 files (was 8, +bin/essentia-ci)
$ git -C <gem> diff --name-only 5360f8f..55d85fb → 9 files (was 8, +.gitignore)
```

Semantic diff, approved round-3 body vs extracted script (normalised: indentation stripped, `'\''`
un-escaped, blank/comment lines removed, new guard block excluded):
```
13c13
< done < <(find spec -type f -name "*_spec.rb" -print0)
> done < "$discovery_file"
30c30
< expected=$(printf "%s" "$dry_run" | ruby -rjson -e
> expected=$(printf "%s" "$dry_run" | ruby -rjson -e '        <-- my normalisation artifact
37c37,40
< missing = fixtures.reject { |fixture| descriptions.any? { |description| description.include?(fixture) } }
> missing = fixtures.reject do |fixture|
>   pattern = /\b#{Regexp.escape(fixture)}\b/
>   descriptions.any? { |description| description.match?(pattern) }
> end
```

Gate presence checklist against `bin/essentia-ci` — 15/15 PRESENT (strict mode · boundary pattern ·
discovery grep_status guard · array-length non-vacuity · Rails-free rejection · rails-free grep_status
guard · fixture floor · dry-run failure_count · dry-run load errors · fixture→example binding · floor
assertion · real-run status · final count equality · traversal-must-succeed · anchored binding).

```
$ ls -l bin/essentia-ci        → -rwxr-xr-x … 2470
$ git ls-files -s bin/essentia-ci → 100755 …
$ grep -nE '^/?bin' .dockerignore → (none; bin/ ships)
$ shellcheck bin/essentia-ci   → SHELLCHECK CLEAN
$ bash -n bin/essentia-ci      → SYNTAX OK
$ grep -rn essentia-ci . → only .github/workflows/ci.yml:112 and :124
```

Entry-form equivalence (from a deliberately wrong CWD, the one deterministic path outside the image):
```
bash <script>   → "find: spec: No such file or directory" / "Failed to discover Essentia spec candidates"  exit=1
<script>        → byte-identical output                                                                    exit=1
```

Integrity matrix: the ten rows in §1.

Suites and lint at the round-4 HEADs (gate is zero failures):
```
app: 276 examples, 0 failures  ·  201 files inspected, no offenses detected
gem:  67 examples, 0 failures  ·   30 files inspected, no offenses detected
```

**What I did not do:** did not rebuild the amd64 image (relying on the implementer's run of the real job
plus your pre-verification), and made no claim about gem CI on GitHub. **No file in either repo was
modified** — all mutation testing was on copies under the session scratchpad.

VERDICT: APPROVE
