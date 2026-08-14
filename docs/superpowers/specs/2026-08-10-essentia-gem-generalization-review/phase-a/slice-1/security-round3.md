# ESSENTIA-GEM-V2 Phase A Slice 1 — Security Re-review Round 3

## Findings

### MUST-FIX — Discovery still ignores a failing `find`

The Round 2 filename injection and `grep` error bypass are closed. However, app
`.github/workflows/ci.yml` feeds the loop with process substitution:

```bash
done < <(find spec -type f -name "*_spec.rb" -print0)
```

The producer runs asynchronously and its exit status is not the loop's status. `set -euo pipefail`
does not observe it. If `find` emits some paths and then fails on another subtree, the array remains
nonempty and the job continues with an incomplete spec set. I reproduced this with one readable
tagged spec plus one inaccessible tagged-spec directory: `find` printed “Permission denied,” while
the main body returned 0 with `array_count=1`.

This is a fail-open discovery gate. The container runs as UID 1000, so traversal errors are possible;
PR-controlled image content can also create such a subtree. Capture discovery through a mechanism
whose producer status is explicitly checked before using the array (for example, write NUL output to
a temporary file under `set -e`, then read it).

No SHOULD-FIX or NIT findings.

## Prior Finding Disposition

- **Hostile whitespace filename argument injection — CLOSED.** NUL-delimited discovery plus
  `"${spec_files[@]}"` preserves the hostile name as one argument: `array_count=1`,
  `argv_count=1`.
- **`grep` error silently bypasses Rails-free guard — CLOSED.** A missing path now emits the explicit
  failure message and exits 2; a true no-match exits 1 internally and continues.

The prior fork-PR clearance is unchanged: this diff does not alter triggers, token permissions,
secrets, Docker exclusions, or environment attachment. The lockfile is unchanged from Round 2, so
the platform/artifact clearance also stands. Both updated integrity specs pass and now pin README.

## Evidence

- Reviewed only:
  - app `52141f60a8134146e82aca933233c23cb8a353a9..a5f71fd2dc682518a06ce759bac3a7921169ec25`
  - gem `ac8f24bee584156859fc04f5f1a5a3e99058a5e8..6c56f2915061487ce0cf95add1c529eb37ff47ab`
- `git -C <repo> status --short` → no output for both trees.
- Hostile filename demonstration using the new NUL-array shape:
  ```text
  array_count=1
  argv_count=1
  argv=</tmp/.../evil --require spec_helper _spec.rb>
  ```
- Explicit `grep` branches:
  ```text
  grep: /tmp/essentia-round3-missing-spec.rb: No such file or directory
  Failed to verify Rails-free Essentia spec: /tmp/essentia-round3-missing-spec.rb
  grep_error_branch_exit=2

  no_match_continues
  ```
- Partial traversal reproduction, using the workflow's process-substitution structure:
  ```text
  array_count=1 job_continued=yes
  main_status=0
  find_stderr=find: /tmp/.../z_blocked: Permission denied
  ```
- Container runtime user:
  ```text
  Dockerfile:76: USER 1000:1000
  ```
- Changed files only:
  ```text
  app: .github/workflows/ci.yml
       spec/baseline_v0_1_0_integrity_spec.rb
  gem: spec/baseline_v0_1_0_integrity_spec.rb
  ```
- Integrity specs:
  ```text
  app: 1 example, 0 failures
  gem: 1 example, 0 failures
  ```
- `git diff --check` on both scoped ranges → no output.

VERDICT: REJECT
