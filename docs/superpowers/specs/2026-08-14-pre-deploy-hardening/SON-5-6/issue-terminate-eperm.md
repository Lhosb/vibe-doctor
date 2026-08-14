## Problem

`terminate` on the subprocess timeout path rescues only `Errno::ESRCH`. It has the same
`Errno::EPERM` exposure that was just found and fixed in `kill_group` on the bounded-read path
(#6).

The race: the child often exits between the decision to kill it and the kill itself. On macOS a
reaped group leader answers **`EPERM`**, not `ESRCH`, so the rescue does not catch it and the
error escapes.

## Evidence this is real, not theoretical

It was found by execution, not inspection, during #6. The new bounded-read specs surfaced it in
`kill_group`; the fix there now rescues both. `terminate` is byte-identical to its state at
`d514137` and was deliberately left out of scope for #6, since widening it would have touched
pre-existing timeout behaviour.

The Test reviewer confirmed the exposure independently and confirmed the out-of-scope call was
correct.

## The portability trap — this is why it needs a real gate, not just a wider rescue

**Linux answers `ESRCH` where macOS answers `EPERM`.**

So on Linux CI, dropping `EPERM` from a rescue would likely **not** fail. Anyone simplifying this
code off a green Linux run would silently reintroduce the bug on macOS, where most of this
project's development happens.

That was measured on the #6 fix: dropping `Errno::EPERM` from `kill_group`'s rescue produced
failures in **10 of 10 runs** on macOS — the race is nondeterministic, so a single run is not
sufficient evidence either way.

## Required work

- Rescue both `Errno::ESRCH` and `Errno::EPERM` in `terminate`, matching the `kill_group` fix.
- Add a spec that gates it. Because the race is nondeterministic, the gate must be run
  **repeatedly** to be meaningful — a single green run proves nothing.
- Record the Linux/macOS divergence in a comment at the rescue, so the next person to "simplify"
  it off a green Linux run knows why both are listed.

## Provenance

Disclosed by the implementer of #6 rather than quietly fixed out of scope, and independently
confirmed by the Test reviewer, 2026-08-14.
