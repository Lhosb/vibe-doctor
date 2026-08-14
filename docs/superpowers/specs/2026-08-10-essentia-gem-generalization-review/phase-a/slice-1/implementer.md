Status: DONE_WITH_CONCERNS

- BASE_SHA (app): `a99c3973a40ebd075469a0d841cbcf09b4e4809c`
- HEAD_SHA (app): `710620db9cac66e8ce00811611131ad2dc6f22b0`
- BASE_SHA (gem): `5360f8fd8609eae39edb5dfab8a07f6439a0b137`
- HEAD_SHA (gem): `55d85fb246e45581172d58066c24e41c8970ac9b`

## Per-finding disposition

| Finding | Disposition |
| --- | --- |
| User decision — extract nested shell | Completed. The gate now lives at executable `bin/essentia-ci`, matching the app's flat `bin/` command convention and ensuring it is copied into `/rails/bin` by the existing Dockerfile. The workflow invokes `/rails/bin/essentia-ci`. |
| ShellCheck enforcement | Added `shellcheck bin/essentia-ci` to the app Essentia job. ShellCheck caught a temporary recreation of the round-2 unquoted-array bug with SC2068, then passed after restoration. |
| MUST-FIX 1 — process substitution hides `find` failure | Fixed. `find -print0` writes to a temporary file and must succeed before the NUL-delimited array is read. Partial output is never consumed after failure. |
| SHOULD-FIX 2 — unanchored fixture substring | Fixed with `/\b#{Regexp.escape(fixture)}\b/`. `sine_44.json` no longer binds to the `sine_440` description. |
| NIT 3 — dotfiles make local suite nondeterministic | Fixed in both integrity specs by excluding dot-prefixed directory entries while still rejecting all non-dot additions. Added `/.DS_Store` to the gem `.gitignore`, matching the app convention. |

## Path and pattern rationale

`bin/essentia-ci` was chosen because Vibe Doctor already exposes repository commands as flat executables under `bin/`, and the Docker image copies the whole app to `/rails`. No mount, packaging change, or duplicated workflow logic is required.

The app commit message and script comment record the structural reason: three review rounds found three Bash-semantics defects hidden inside YAML, Docker, and quoted `bash -c`; a checked-in script can be linted and directly tested.

## Diff --stat

```text
$ git -C /Users/lukeolson/projects/vibe-doctor diff --stat a99c3973a40ebd075469a0d841cbcf09b4e4809c..HEAD
 .github/dependabot.yml                             |  2 +
 .github/workflows/ci.yml                           | 11 ++--
 bin/essentia-ci                                    | 72 ++++++++++++++++++++++
 spec/baseline_v0_1_0_integrity_spec.rb             | 25 ++++++++
 spec/fixtures/mood_probe/baseline_v0_1_0/README.md |  9 +++
 .../fixtures/mood_probe/baseline_v0_1_0/chirp.json |  8 +++
 .../mood_probe/baseline_v0_1_0/clicks.json         |  8 +++
 .../mood_probe/baseline_v0_1_0/sine_440.json       |  8 +++
 .../mood_probe/baseline_v0_1_0/white_noise.json    |  8 +++
 9 files changed, 146 insertions(+), 5 deletions(-)
```

```text
$ git -C /Users/lukeolson/projects/gems/mood_probe diff --stat 5360f8fd8609eae39edb5dfab8a07f6439a0b137..HEAD
 .github/workflows/ci.yml                           | 37 ++++++++++++++++++++++
 .gitignore                                         |  1 +
 Gemfile.lock                                       |  1 +
 spec/baseline_v0_1_0_integrity_spec.rb             | 21 ++++++++++++
 spec/fixtures/mood_probe/baseline_v0_1_0/README.md |  9 ++++++
 .../fixtures/mood_probe/baseline_v0_1_0/chirp.json |  8 +++++
 .../mood_probe/baseline_v0_1_0/clicks.json         |  8 +++++
 .../mood_probe/baseline_v0_1_0/sine_440.json       |  8 +++++
 .../mood_probe/baseline_v0_1_0/white_noise.json    |  8 +++++
 9 files changed, 101 insertions(+)
```

Both trees are clean. Nothing was pushed and no PR was opened.

## Evidence

### ShellCheck failing and passing states

Temporary unquoted array expansion:

```text
$ shellcheck bin/essentia-ci
bin/essentia-ci line 47:
dry_run=$(bundle exec rspec ${spec_files[@]} --tag essentia --dry-run --format json)
                            ^--------------^ SC2068 (error): Double quote array expansions to avoid re-splitting elements.
SHELLCHECK_FAILING_STATE_EXIT=1
```

Restored script:

```text
$ shellcheck bin/essentia-ci
shellcheck_exit=0
```

CI wiring:

```text
$ ruby -ryaml -e '<assert Essentia job runs shellcheck bin/essentia-ci>' .github/workflows/ci.yml
shellcheck CI step present
```

### Checked discovery producer

Temporary unreadable `spec/z_blocked` directory:

```text
$ bin/essentia-ci
find: spec/z_blocked: Permission denied
Failed to discover Essentia spec candidates
DISCOVERY_FAILURE_EXIT=1
```

Passing control after restoring/removing the directory:

```text
$ bin/essentia-ci
Finished in 6.77 seconds (files took 0.07833 seconds to load)
5 examples, 0 failures
```

### Anchored fixture binding

Passing control with two unrelated tagged examples, demonstrating count slack is permitted:

```text
$ bin/essentia-ci
Finished in 6.8 seconds (files took 0.07484 seconds to load)
7 examples, 0 failures
```

Failing state with additional orphan `sine_44.json`:

```text
$ bin/essentia-ci
Golden fixtures without an Essentia example: sine_44
ANCHORED_BASENAME_GATE_EXIT=1
```

### Dotfile determinism

With `.DS_Store` present in both baseline directories:

```text
$ bundle exec rspec spec/baseline_v0_1_0_integrity_spec.rb
1 example, 0 failures
```

Both repos passed.

With non-dot `notes.txt` present:

```text
expected: ["README.md", "chirp.json", "clicks.json", "sine_440.json", "white_noise.json"]
     got: ["README.md", "chirp.json", "clicks.json", "notes.txt", "sine_440.json", "white_noise.json"]
1 example, 1 failure
APP_NONDOT_GATE_EXIT=1
GEM_NONDOT_GATE_EXIT=1
```

All temporary fault-injection files and directories were removed before commit.

### Rebuilt amd64 image and real job

```text
$ docker build --platform linux/amd64 -t vibe-doctor-essentia-final .
$ docker run --rm --platform linux/amd64 \
    --entrypoint /rails/bin/essentia-ci \
    -e ESSENTIA_SPECS=1 -e RAILS_ENV=test \
    vibe-doctor-essentia-final
...
Finished in 17.49 seconds (files took 0.12225 seconds to load)
5 examples, 0 failures
```

### Final suites and lint

```text
$ cd /Users/lukeolson/projects/vibe-doctor && bundle exec rspec
Finished in 9.93 seconds (files took 2.21 seconds to load)
276 examples, 0 failures
```

```text
$ cd /Users/lukeolson/projects/vibe-doctor && bundle exec rubocop
Inspecting 201 files
201 files inspected, no offenses detected
```

```text
$ cd /Users/lukeolson/projects/gems/mood_probe && bundle exec rspec
Finished in 1.48 seconds (files took 0.14755 seconds to load)
67 examples, 0 failures
Randomized with seed 22822
```

```text
$ cd /Users/lukeolson/projects/gems/mood_probe && bundle exec rubocop
Inspecting 30 files
30 files inspected, no offenses detected
```

### Commit rationale

```text
$ git -C /Users/lukeolson/projects/vibe-doctor show --format=full --no-patch HEAD
commit 710620db9cac66e8ce00811611131ad2dc6f22b0

    Add mood_probe rollback guardrails

    Keep the Essentia gate in bin/essentia-ci so ShellCheck and direct tests can catch Bash defects that nested YAML, Docker, and quoted shell strings hid across three review rounds.
```

### Rollback anchor

```text
$ git -C /Users/lukeolson/projects/gems/mood_probe rev-parse v0.1.0^{}
5360f8fd8609eae39edb5dfab8a07f6439a0b137
```

The annotated tag remains local and unpushed.

## Deferred residuals

- Text discovery cannot see metadata applied indirectly through `define_derived_metadata`, support files, or shared example groups.
- The Rails-free constraint narrows the deferred F.2 mirror; a Rails-dependent mirror needs a database-backed job.
- `ESSENTIA_SPECS=1` remains redundant with `--tag essentia`.
- Gem CI shape uses `.tool-versions`, not `.ruby-version`.
- Future G1 must glob `*.json`.
- `command_runner_spec` flake, repository-wide action SHA pins/permissions, G1, F.2 mirror, and Docker-backed gem jobs remain separately deferred.

## Gem CI execution status

The gem workflow commands pass locally on Ruby 4.0.1 and the lockfile includes `x86_64-linux`. **GitHub Actions green remains unverified until the gem commit is pushed.** No push was performed.

RISK TRIGGERS TOUCHED: external automation configuration, a new checked-in CI executable, and dependency lockfile platform metadata; no migrations, authz, data exposure, destructive operations, runtime external integrations, or new dependencies.

Restructuring beyond instructions: user-directed extraction of the Essentia gate from workflow YAML to `bin/essentia-ci`.
