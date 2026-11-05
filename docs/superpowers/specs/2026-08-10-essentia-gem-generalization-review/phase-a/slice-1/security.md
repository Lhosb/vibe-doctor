# ESSENTIA-GEM-V2 Phase A Slice 1 — Security Review

## Findings

### SHOULD-FIX — Pin workflow actions to immutable commit SHAs

The gem's first workflow uses `actions/checkout@v6` and `ruby/setup-ruby@v1` at
`.github/workflows/ci.yml:14,17,30,33`. Both references are mutable: GitHub currently resolves
`actions/checkout@v6` to `d23441a48e516b6c34aea4fa41551a30e30af803`, while
`ruby/setup-ruby@v1` is a moving branch currently at
`95ef2b042f9d7a56d8268cba8559e2842e2ad01b`. These are established actions (`actions` is GitHub's
official organization; `ruby/setup-ruby` is the standard Ruby setup action), but immutable SHA pins
would reduce tag/branch retargeting and upstream-account compromise risk. This is not a release
blocker here because the workflow has a read-only token, no secrets or environments, and runs only
tests/lint.

No MUST-FIX or NIT findings.

## Security Assessment

- **X1 — nested shell:** APPROVE. The changed shell at app `.github/workflows/ci.yml:117-124`
  contains no GitHub expression (`${{ ... }}`), event payload, branch/ref, input, secret, filename,
  or other PR-author-controlled value interpolated into the shell program. `expected` comes only from
  RSpec JSON output and is used as data inside a quoted regex; `output` is printed with
  `printf "%s\n"`. A fork PR can change checked-out repository code and therefore execute its own
  code in this ordinary unprivileged `pull_request` CI job, but it cannot inject into a privileged
  shell context or obtain secrets through this change.
- **X2 — gem workflow:** APPROVE with the SHA-pinning hardening above. Triggers are only
  `pull_request` and pushes to `main`; there is no `pull_request_target`, `workflow_run`,
  `workflow_dispatch` input, or secret-bearing environment. The public repository setting reports
  `default_workflow_permissions: read` and `can_approve_pull_request_reviews: false`. Repository
  Actions secrets and environments both report zero entries. No secret is passed to PR-controlled
  code.
- **X3 — Dependabot:** APPROVE. The ignore is nested only under the root Bundler ecosystem entry and
  names exactly `mood_probe`; the separate GitHub Actions updater and all other gems remain
  unsuppressed. Security trade-off: Dependabot will no longer notify or open app PRs when the
  git-sourced `mood_probe` advances, so deliberate human review/tag pin updates must carry that
  responsibility. This is the intended rollback guardrail.
- **X4 — frozen JSON:** APPROVE. All eight committed copies contain only six numeric model-output
  fields. Searches found no credentials, tokens, URLs, usernames, email addresses, hostnames, local
  paths, IPs, or PII. Every JSON file is byte-identical to its pre-existing source golden.
- **X5 — seven design constraints:** No weakening. The reviewed diff changes no Ruby, Python,
  dependency manifest/lockfile, Dockerfile, registry, planner, mapper, persistence, endpoint, or
  runtime integration surface. It does not alter the constrained instruction set, trusted
  registration, artifact/output bounds, explicit packs, embedding exposure, or licensing behavior.

## Evidence

- Diff range reviewed:
  - app `a99c3973a40ebd075469a0d841cbcf09b4e4809c..9e28d3fd5f6442acaa1ee6452865f720d3ab6cfb`
  - gem `5360f8fd8609eae39edb5dfab8a07f6439a0b137..f0f8127d94300d08e383e6400be04b0ff4658dd9`
- Required documents read: app `CLAUDE.md`; authoritative design §C, §E.1, §F.2–F.3,
  §J.3 items 7/8/14, §J.4 G1, §J.5; Principal sequencing review; implementer report; app and gem
  READMEs; app `.github/copilot-instructions.md`; `team-facts`.
- `git -C /Users/lukeolson/projects/vibe-doctor status --short` and
  `git -C /Users/lukeolson/projects/gems/mood_probe status --short`
  → no output; both worktrees clean.
- `git -C /Users/lukeolson/projects/vibe-doctor diff --name-status
  a99c3973a40ebd075469a0d841cbcf09b4e4809c..9e28d3fd5f6442acaa1ee6452865f720d3ab6cfb`
  → only `.github/dependabot.yml`, `.github/workflows/ci.yml`, and the five frozen-baseline files.
- `git -C /Users/lukeolson/projects/gems/mood_probe diff --name-status
  5360f8fd8609eae39edb5dfab8a07f6439a0b137..f0f8127d94300d08e383e6400be04b0ff4658dd9`
  → only `.github/workflows/ci.yml` and the five frozen-baseline files.
- Runtime-surface checks with `git diff --quiet ... -- '*.rb' '*.py' Gemfile Gemfile.lock
  '*.gemspec' Dockerfile*`
  → `app behavior-surface diff exit=0`; `gem behavior-surface diff exit=0`.
- YAML parsing of both workflows:
  - app → `permissions: nil`, triggers `pull_request` and push to `main`, five existing jobs.
  - gem → `permissions: nil`, triggers `pull_request` and push to `main`, jobs `rspec` and `lint`,
    actions `actions/checkout@v6` and `ruby/setup-ruby@v1`.
- `gh api repos/Lhosb/mood_probe/actions/permissions/workflow`
  → `{"default_workflow_permissions":"read","can_approve_pull_request_reviews":false}`.
- `gh api repos/Lhosb/mood_probe/actions/secrets`
  → `{"names":[],"secret_count":0}`.
- `gh api repos/Lhosb/mood_probe/environments`
  → `{"environment_count":0,"names":[]}`.
- Action resolution:
  - `actions/checkout@v6` → commit `d23441a48e516b6c34aea4fa41551a30e30af803`.
  - `ruby/setup-ruby@v1` → branch commit `95ef2b042f9d7a56d8268cba8559e2842e2ad01b`.
- Nested-shell interpolation check over app workflow lines 112–140:
  → no `${{` matches; shell text contains only fixed literals and command-derived variables.
- Fixture scan command:
  `git -C <repo> grep -nEi '(secret|token|password|api[_-]?key|authorization|bearer|/Users/|/home/|hostname|email|user(name)?|ip(_address)?|https?://)' HEAD -- spec/fixtures/mood_probe/baseline_v0_1_0`
  → no matches in either repository.
- Byte comparison:
  `cmp` for `chirp`, `clicks`, `sine_440`, and `white_noise` in both repositories
  → `all frozen JSON files match their source goldens byte-for-byte`.
- `git diff --check` on both exact ranges → no output.
- Documented app scanners:
  `ruby -C /Users/lukeolson/projects/vibe-doctor bin/brakeman --no-pager &&
  ruby -C /Users/lukeolson/projects/vibe-doctor bin/bundler-audit &&
  ruby -C /Users/lukeolson/projects/vibe-doctor bin/importmap audit`
  → Brakeman `Security Warnings: 0`; Bundler Audit `No vulnerabilities found`;
  Importmap audit `No vulnerable packages found`.
- Gem security-tool discovery found no documented scanner executable/config beyond its lockfile and
  gemspec; no gem scanner was available to run.

VERDICT: APPROVE-WITH-CHANGES
