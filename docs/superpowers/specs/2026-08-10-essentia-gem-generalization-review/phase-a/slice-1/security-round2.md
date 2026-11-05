# ESSENTIA-GEM-V2 Phase A Slice 1 — Security Re-review Round 2

## Findings

### MUST-FIX — Preserve discovered spec paths as an array; fail on `grep` errors

App `.github/workflows/ci.yml:120-132` stores newline-delimited paths in `spec_files`, then expands
`$spec_files` unquoted into `grep` and both RSpec commands. Shell metacharacters in a filename are not
recursively evaluated, so this is **not direct shell-command injection**. It is nevertheless
word-splitting, pathname expansion, and downstream argument injection.

A PR author can add a tagged path containing whitespace so its split words include RSpec options such
as `--require <repo-file>`. RSpec accepts options produced by this split; the evidence below shows an
unquoted value becoming three arguments and loading the injected `--require` target. The same value is
first passed to `grep`. An option-like split word can make `grep` exit 2, but because the command is
the condition of `if grep ...; then`, `set -e` is disabled for that command and every nonzero status
is treated as “no `rails_helper` found.” The job then proceeds. Thus a crafted filename can bypass the
new Rails-free-set guard and load Ruby outside the discovered tagged-file set.

Concrete path: a fork PR adds an Essentia-tagged path whose whitespace-separated representation is an
existing spec path, `--require`, and an untagged Ruby file. The guard's `grep` receives the injected
option, errors, and continues; both RSpec invocations honor `--require` and execute the untagged file.
This does not expose a secret—the PR already controls the Docker build and the container has no token
or key—but it defeats MF-1's promised execution boundary and makes the CI gate's selected input differ
from its reviewed/discovered input.

Use a NUL-delimited Bash array (for example, `mapfile -d ''` with NUL-producing discovery), pass
`"${spec_files[@]}"` everywhere, use `--` where supported, and distinguish `grep` exit 1 (“no
matches”) from exit 2 (“error”).

No SHOULD-FIX or NIT findings. The prior SHA-pinning/permissions recommendation remains deferred to
the already-routed repo-wide CI-hardening ticket and is not re-filed.

## Round 1 Finding Disposition

- **MF-1 Rails/database isolation — NOT CLOSED.** The normal current filename set is Rails-free and
  the implementer's container run is valid, but hostile filenames can inject arguments and the guard
  masks `grep` errors as success.
- **MF-2 non-vacuity oracle — CLOSED.** The independent `golden/*.json + 1` floor is present;
  `set -euo pipefail` makes discovery/dry-run pipeline failures red. It remains subject to the
  MUST-FIX argument-boundary issue above.
- **MF-3 frozen-byte gate — CLOSED.** Both specs independently pin the exact four-file set and four
  literal SHA-256 values; both targeted specs pass.
- **MF-4 Ruby/platform — CLOSED.** The workflow no longer overrides Ruby 3.2, and the lockfile adds
  `x86_64-linux` without changing the resolved `GEM` section.
- **SF-5 retirement text — CLOSED.** Both READMEs contain the E.1 retirement block verbatim.

## Scoped Security Assessment

- **X1 — command/argument injection:** No recursive shell execution from `;`, `$()`, or similar
  characters, but unquoted `$spec_files` permits RSpec/grep argument injection and must be fixed.
  File content only determines discovery; the filename is the unsafe argument source.
- **X2 — fork PR exposure:** The app workflow triggers on `pull_request` and pushes to `main`, so a
  fork PR can reach the job subject to GitHub's normal fork-workflow approval policy. PR-controlled
  Dockerfile/repository content therefore executes in the build and container. The repository's
  workflow token default is read-only; repository Actions secrets are empty; no environment is
  referenced; `docker run` passes only `ESSENTIA_SPECS` and `RAILS_ENV`. `.dockerignore` excludes
  `.git/` (including checkout's persisted credential), `.env*`, `config/master.key`, credential
  keys, and `.github`. No GitHub token, Rails key, or Actions secret is reachable through this job.
- **X3 — `set -euo pipefail`:** The dry-run pipeline and real RSpec run are fail-closed. The
  `set +e` window captures the real RSpec exit status, immediately restores `set -e`, prints output,
  and fails at `test "$status" -eq 0`. The exception is the `if grep` guard: Bash intentionally
  suppresses `errexit` in conditionals, and the code does not distinguish no-match from operational
  error, producing the MUST-FIX above.
- **X4 — lockfile platform:** Adding `x86_64-linux` changes no resolved gem/version/checksum entry
  and introduces no platform-specific native artifact in this lockfile. Linux may compile the
  existing generic native gems (for example `json`/`racc`) as before; no new supplier or binary gem
  is selected. Future lock updates may record platform variants, but those will be explicit diffs.
- **X5 — SHA-256 anchors:** The constants are meaningful regression anchors, not a runtime
  recomputation of expected values: they are independent literals, and the specs also pin the exact
  filename set, so mutation, addition, or deletion fails. They do not defend against a malicious
  change that updates both fixture and expected digest in the same reviewed commit; code review and
  the “never edit” policy remain the authority for that case. That limitation is appropriate here.

## Evidence

- Scoped diff ranges reviewed:
  - app `9e28d3fd5f6442acaa1ee6452865f720d3ab6cfb..52141f60a8134146e82aca933233c23cb8a353a9`
  - gem `f0f8127d94300d08e383e6400be04b0ff4658dd9..ac8f24bee584156859fc04f5f1a5a3e99058a5e8`
- Required inputs read: `CLAUDE.md`, Round 2 implementer report, Round 1 security report,
  `team-facts`, and every file in both scoped diffs.
- `git -C <repo> status --short` for both repositories → no output; both trees clean.
- App discovery:
  ```text
  $ git -C /Users/lukeolson/projects/vibe-doctor grep -lE \
      '(:essentia|essentia:[[:space:]]*true)' 52141f60... -- 'spec/**/*_spec.rb'
  spec/integration/essentia_extract_golden_spec.rb

  rails_helper matches:
  (none)
  ```
- App workflow/Docker boundary:
  ```text
  on:
    pull_request:
    push:
      branches: [ main ]

  .dockerignore:
  /.git/
  /.env*
  /config/master.key
  /config/credentials/*.key
  /.github
  ```
- App repository settings:
  ```text
  $ gh api repos/Lhosb/vibe-doctor/actions/permissions/workflow
  {"default_workflow_permissions":"read","can_approve_pull_request_reviews":false}

  $ gh api repos/Lhosb/vibe-doctor/actions/secrets --jq ...
  {"names":[],"secret_count":0}

  $ gh api repos/Lhosb/vibe-doctor/environments --jq ...
  {"environment_count":1,"names":["copilot"]}
  ```
  The workflow references no environment.
- RSpec argument-injection demonstration:
  ```text
  $ spec_files='/Users/.../baseline_v0_1_0_integrity_spec.rb --require /Users/.../spec_helper.rb'
  $ for arg in $spec_files; do printf ' <%s>' "$arg"; done
  expanded argv: </Users/.../baseline_v0_1_0_integrity_spec.rb> <--require> </Users/.../spec_helper.rb>

  $ BUNDLE_GEMFILE=/Users/lukeolson/projects/vibe-doctor/Gemfile bundle exec rspec \
      -I/Users/lukeolson/projects/vibe-doctor/spec $spec_files --dry-run --format progress
  1 example, 0 failures
  ```
  This proves split filename words are interpreted as an RSpec option and required file.
- Conditional error masking:
  ```text
  $ set -e; if grep -l rails_helper --definitely-not-a-grep-option; then echo guarded; fi; echo continued
  script continued after if; status=0; grep_error=grep: unrecognized option `--definitely-not-a-grep-option'
  ```
- Real-RSpec failure window simulation:
  ```text
  simulated-rspec-failure
  body_exit=1
  ```
- Dry-run pipeline failure simulation:
  ```text
  dry_run_pipeline_exit=1
  ```
- Integrity specs:
  ```text
  $ BUNDLE_GEMFILE=/Users/lukeolson/projects/vibe-doctor/Gemfile bundle exec rspec \
      -I/Users/lukeolson/projects/vibe-doctor/spec --require spec_helper \
      /Users/lukeolson/projects/vibe-doctor/spec/baseline_v0_1_0_integrity_spec.rb
  1 example, 0 failures

  $ BUNDLE_GEMFILE=/Users/lukeolson/projects/gems/mood_probe/Gemfile bundle exec rspec \
      -I/Users/lukeolson/projects/gems/mood_probe/spec --require spec_helper \
      /Users/lukeolson/projects/gems/mood_probe/spec/baseline_v0_1_0_integrity_spec.rb
  1 example, 0 failures
  ```
- Actual app baseline SHA-256 output exactly matches the four literals in both specs:
  `b2a04b...`, `50c7ee...`, `1c4bfb...`, `7a1725...`.
- Lockfile:
  ```text
  $ git -C /Users/lukeolson/projects/gems/mood_probe diff f0f8127..ac8f24b -- Gemfile.lock
  +  x86_64-linux

  $ diff <(git show f0f8127:Gemfile.lock | sed -n '/^GEM$/,/^PLATFORMS$/p') \
         <(git show ac8f24b:Gemfile.lock | sed -n '/^GEM$/,/^PLATFORMS$/p')
  (no output)
  GEM resolution sections identical

  $ BUNDLE_GEMFILE=/Users/lukeolson/projects/gems/mood_probe/Gemfile bundle platform
  Your app has gems that work on these platforms:
  * arm64-darwin-25
  * ruby
  * x86_64-linux
  ```
- `git diff --check` on both scoped ranges → no output.
- No GitHub Actions result is claimed for the new gem workflow; it remains unexecuted until pushed.

VERDICT: REJECT
