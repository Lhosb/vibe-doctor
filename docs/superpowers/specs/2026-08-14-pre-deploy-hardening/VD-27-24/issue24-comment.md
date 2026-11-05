## Coverage requirement satisfied by `d3ff0b9`. Two reviewers, both re-derived independently.

BASE `5c9dfcc` → HEAD `d3ff0b9`, branch `fix/pre-deploy-record-and-clamp-coverage`.
Production `essentia_mapper.rb` has **zero diff** — this is a coverage-only change.

**Spec review — APPROVE.** The reviewer re-derived all eight clamp mutations rather than trusting
the implementer's matrix: 8 of 8 caught, each by exactly the example its name promises, with a
passing unmutated control run first. The same harness was replayed against BASE and it misses
precisely the four bounds this issue named — danceability lower, mood_relaxed lower,
mood_acoustic upper, mood_happy upper. **The issue's diagnosis is confirmed and the fix closes
exactly those four.**

**Code quality review — APPROVE.** Independently re-ran everything: 299 examples / 0 failures,
rubocop 207 files / 0 offenses, brakeman 0 warnings. Confirmed `essentia_mapper.rb` byte-identical
to `origin/main` by SHA-256.

Example names were checked against their bodies: `:63` asserts all four heads `eq 0.0`, `:72`
asserts all four `eq 1.0`. No spec asserts something other than what its name claims.

The transposition-detection property called out in the helper comment **survives** — verified not
by reading but by mutating the mapper to swap valence/arousal, which is caught by three examples
at HEAD, not just the one the comment names.

---

## ⚠️ A trap this change introduces — read before touching this file again

The two new examples set all four softmax heads to the **same value**. That means they no longer
detect a **crosswired head**, which the deleted BASE example did incidentally, via its distinct
`1.1 / -0.1 / 1.1 / -0.1` pattern.

Proven with a mutation where `mood_happy` reads `danceability_musicnn`: **both new examples stay
green.**

This is **not** a suite regression today. `maps native descriptor values` at `:27` still catches
it, because its defaults are distinct (`0.2 / 0.3 / 0.4 / 0.6`).

**But that example is now the sole guard.** Tidying it to use the new `softmax_value:` helper —
which looks like an obvious cleanup — would silently delete crosswiring detection from the entire
suite. Anyone refactoring this file should treat those distinct defaults as load-bearing.

---

## This issue is not closed by `d3ff0b9`

Its second comment requires more than coverage: a recorded decision on **skip the track vs.
include it saturated**, plus an assertion on the contributing count. That commit contains no such
decision, correctly, because the dispatch was scoped to coverage only.

The policy decision is split into its own issue and remains open. Closing this one on the
coverage fix alone would lose it.
