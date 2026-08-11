# ESSENTIA-GEM-V2 Phase A Slice 1 — Security Round 4

## Findings

No MUST-FIX, SHOULD-FIX, or NIT findings.

## Prior Finding Disposition

- **Process-substitution discovery failure — CLOSED.** `find` must finish successfully into a
  temporary file before the array is read. Re-running the partial-traversal attack against the actual
  `bin/essentia-ci` produced exit 1 and never consumed the partial list.
- **Whitespace filename injection / swallowed `grep` status — remain CLOSED.** The extracted script
  retains the NUL-delimited array, quoted expansions, `--` separators, and explicit status branches.

## Extraction Security

`mktemp` creates an unpredictable mode-0600 file; all accesses are quoted; the EXIT trap removes it
on normal/error exits. There is no predictable-name, symlink, or TOCTOU issue of concern in this
single-process ephemeral container. ShellCheck is clean. No remaining unsafe array expansion or
swallowed discovery/grep/RSpec status was found.

The shipped `--entrypoint bash ... /rails/bin/essentia-ci` form is equivalent to the implementer's
direct-script entrypoint for this script: Bash receives the path as its script operand. The evidence
gap mattered enough to rerun, and the exact shipped invocation passed, so no further change is needed.

Earlier clearances stand: the Round 4 delta does not change triggers, token scope, secrets,
Docker credential exclusions, or the lockfile platform/artifact resolution.

## Evidence

```text
$ (partial traversal) /Users/lukeolson/projects/vibe-doctor/bin/essentia-ci
script_exit=1
find: spec/z_blocked: Permission denied
Failed to discover Essentia spec candidates
```

```text
$ shellcheck /Users/lukeolson/projects/vibe-doctor/bin/essentia-ci
shellcheck_exit=0

$ stat -f 'temp_mode=%Sp' "$(mktemp)"
temp_mode=-rw-------
```

Exact shipped command:

```text
$ docker run --rm --platform linux/amd64 --entrypoint bash \
    -e ESSENTIA_SPECS=1 -e RAILS_ENV=test \
    vibe-doctor-essentia-final /rails/bin/essentia-ci
Finished in 18.17 seconds
5 examples, 0 failures
```

`git diff --check` and `git -C <repo> status --short` for both scoped trees produced no output.

VERDICT: APPROVE
