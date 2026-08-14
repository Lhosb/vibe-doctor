# Phase A, Slice 1 Review Record

This directory preserves the four-round implementation review for the rollback-surviving infrastructure slice.

Final commits:

- App: `710620db9cac66e8ce00811611131ad2dc6f22b0`
- Gem: `55d85fb246e45581172d58066c24e41c8970ac9b`

## Review arc

1. Round 1 found that the widened Essentia CI load set booted Rails without a database, the example-count oracle was vacuous, the frozen baseline had no executable integrity gate, and gem CI used the wrong Ruby/platform assumptions.
2. Round 2 found Bash filename option injection and grep-error bypasses, an overbroad `:essentia` text match, incomplete README integrity coverage, and a fixture-count floor that could pass while a specific fixture had no example.
3. Round 3 found that process substitution hid partial or failed `find` traversal, fixture binding used an unanchored substring, and dotfiles made integrity checks locally nondeterministic. Repeated defects in the nested YAML/Docker/Bash body led to the decision to extract it.
4. Round 4 confirmed the extracted, ShellCheck-gated `bin/essentia-ci` closed every blocking finding. It also recorded the remaining testability, automated-coverage, and narrow dotfile-integrity follow-ups below.

## Deferred or unresolved follow-ups

### 1. Make `bin/essentia-ci` testable and add regression coverage

The script is lintable but not testable without editing a copy because `spec`, `spec/fixtures/mood_probe/golden`, and `bundle exec rspec` are hardcoded. The intended seam is three environment-variable defaults: `SPEC_ROOT`, `GOLDEN_DIR`, and `RSPEC`.

The Round 3 discovery fix has no automated coverage. Add a plain app RSpec spec that shells out to the script against a fixture tree with a stub `rspec` on `PATH`. It must require no Docker or Essentia and run in the existing test job.

Test reviewer priority order:

1. passing control (unmodified inputs exit 0)
2. discovery traversal failure
3. orphan fixture with and without slack
4. prefix-collision fixture
5. discovery matches nothing
6. dead selector
7. `rails_helper` guard fires, and grep error path exits with grep status

### 2. Narrow the integrity-spec dotfile exemption

Excluding every dot-prefixed entry allows `.smuggled.json` or a `.hidden/` directory to pass. The five pinned digests and every non-dot entry remain protected, and git still exposes dotfiles other than the ignored `.DS_Store`. When these specs are next touched, reject only the exact name `.DS_Store`.

### 3. Carry the remaining implementation residuals

- `command_runner_spec` has a 0.2-second PID-file race.
- Both repositories need coordinated CI hardening: action SHA pins and explicit `permissions: contents: read`.
- Text-grep discovery cannot see `define_derived_metadata` or shared-example-group metadata.
- The Rails-free constraint narrows the deferred F.2 mirror.
- `ESSENTIA_SPECS=1` is inert for selection.
- The gem uses `.tool-versions` where the app uses `.ruby-version`.
- The future G1 implementation must glob `*.json`, not `*`.

### 4. Publish the rollback and CI prerequisites

Neither repository was pushed during the slice. Gem CI has never executed, so its green status remains unverified until the gem commit is pushed. The annotated `v0.1.0` tag is local only, so the J.5 rollback procedure is not executable as written. Both actions remain pending the user.
