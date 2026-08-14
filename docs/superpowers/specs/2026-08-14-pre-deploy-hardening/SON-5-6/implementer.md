# SON-5-6 Implementer Report

**Author:** Keystone · **Date:** 2026-08-14
**Repo:** `Lhosb/sonance` (dir `mood_probe`, stale name)
**Branch:** `fix/cli-output-and-bounded-subprocess-reads`

**Status:** IN PROGRESS — written incrementally.

## Identifiers

- BASE_SHA: *(pending)*
- HEAD_SHA: *(pending)*
- Commit 1 (issue #5): *(pending)*
- Commit 2 (issue #6): *(pending)*

## No-conflict compliance

Forbidden files (owned by unmerged `fix/pin-python-stack-and-notice-uris`):
`Dockerfile.essentia`, `constraints.txt`, `spec/support/canonical_essentia_environment.rb`,
`spec/canonical_essentia_environment_spec.rb`, `NOTICE`.
*(compliance verified at end)*

---
## Commit 1 — issue #5: CLI emitted object inspect strings

**BASE_SHA:** `d514137a09facf8c64519e189aed57c3abaf5635` (`origin/main`, `fix: accept current GitHub runner CPUs`)
**Commit 1:** `364b02816592f2a9c05355747a9df7b41f44ee43`

**Files:** `lib/sonance/value.rb`, `spec/cli_spec.rb`, `spec/support/recording_cli_analyze.rb`,
`spec/support/recording_cli_values.rb` (new). **`exe/sonance` unchanged.**

### RED reproduction, before any edit

```
$ ruby -e 'a = AnalysisBuilder...call(requested: %i[bpm_rhythm2013 beat_confidence_rhythm2013], ...)
           puts JSON.pretty_generate(a.to_h)'          # the exact exe/sonance:46 expression
{
  "bpm_rhythm2013": "#<Sonance::Scalar:0x0000000124929058>",
  "beat_confidence_rhythm2013": "#<Sonance::Scalar:0x0000000124928130>"
}
```

### Output format, and why

**Chosen: each descriptor renders the shape the Python backend already emits for its kind** —
scalar as a bare number, vector as a bare array of numbers, categorical and series as objects whose
keys are the keyword sets `AnalysisBuilder` splats back in.

```json
{ "bpm_rhythm2013": 123.5, "embedding_musicnn": [0.001, 0.002, ...] }
```

Reasons, in order of weight:

1. **It is not a new format.** The dispatch warned against inventing one the library contradicts.
   This *is* the library's existing wire format — `sonance_extract.py` emits
   `{"features": {"<id>": <value>}}` with bare numbers for scalars and arrays for vectors, and
   `AnalysisBuilder` consumes exactly that. CLI output and backend output are now the same shape.
2. **It round-trips, and that is asserted.** CLI stdout can be fed straight back into
   `AnalysisBuilder` with no translation step. A spec proves it.
3. **It satisfies issue #5's stated verification literally** — "parseable JSON whose values are
   numbers" — while still representing `embedding_musicnn`, a `Vector` in the default registry that
   a flat number-only format could not express at all.

Rejected: a rich per-value object carrying `kind`/`units`/`provenance`. It would be more
self-describing but would be a format the library layer does not speak, and it would break the
round-trip property. Provenance is available through the library API, which is the right place for it.

**Fixed at the `Value` layer, not in the CLI.** Issue #5 offered either. Fixing `Value#as_json` /
`#to_json` repairs every consumer rather than one call site, and it is what makes the "spec must fail
if `Value#to_json` is removed" check meaningful. `to_json` forwards the generator state so nested
arrays stay properly indented under `JSON.pretty_generate`.

### The spec blindness — fixed, and it was real

The old stub returned `Data.define(:path, :descriptors)`, a JSON-native object. The only object that
reproduces the defect is the `Analysis` the stub replaced, so the spec was structurally blind. The
stub now returns a **real `Analysis` of real `Value` objects** built through the **real
`AnalysisBuilder`** against the **real `Registry.default`**, so `Value` construction runs its actual
validations and the spec exercises the serialization path it claims to cover.

Five examples replace the one that asserted on stub-shaped data: exact scalar values, vector shape and
contents, a whole-registry sweep asserting no `#<Sonance::` appears anywhere in stdout, an
`AnalysisBuilder` round-trip, and a **non-vacuity floor** asserting the stub's payload table covers
every id in `Registry.default` — without which the other four only prove what the stub happens to emit.

**A leak I caught and fixed:** requiring the stub from the main RSpec process monkey-patches
`Sonance::Extractor` suite-wide. Confirmed by execution — `extractor_spec` alone was 9/0, but
`cli_spec` then `extractor_spec` in defined order was **9 failures**. The payload table now lives in
`spec/support/recording_cli_values.rb`, which the coverage example requires instead; the stub file is
loaded only via `RUBYOPT` into the CLI subprocess.

### Mutation battery — both directions

| Mutation | Result |
|---|---|
| **CONTROL** (unmutated) | **7 examples, 0 failures** |
| **M1** — delete `Value#to_json`, the exact removal issue #5 names | **7 examples, 4 failures** |
| **M2** — revert the stub to the old JSON-native `Data` object | **7 examples, 4 failures** |

M1 failure output, showing the defect returning verbatim:

```
expected: {"beat_confidence_rhythm2013" => 3.25, "bpm_rhythm2013" => 123.5}
     got: {"beat_confidence_rhythm2013" => "#<Sonance::Scalar:0x0000000122cd02a8>",
           "bpm_rhythm2013" => "#<Sonance::Scalar:0x0000000122cd0550>"}
expected "#<Sonance::Vector:0x0000000120e90360>" to be a kind of Array
expected "{\n \"valence_emomusic\": \"#<Sonance::Scalar:...\" ... }" not to match /#<Sonance::/
```

M2 is the load-bearing one: it proves the new examples genuinely depend on a real `Analysis` and
would not pass against the blindness that hid this defect for two releases.

Both mutations were applied to the committed tree and reverted with `git checkout --`; working tree
verified clean afterwards.

---
## Commit 2 — issue #6: unbounded subprocess stream reads

**Commit 2 / HEAD_SHA:** `3f1f5110464e0a795481af6328d8506af1d5c499`

**Files:** `lib/sonance/backends/essentia_python.rb`, `spec/backends/command_runner_spec.rb`,
`spec/backends/essentia_python_spec.rb`.

### What changed

`CommandRunner` read both streams with an unbounded `String#read` before any protocol parsing. Both
reads are now chunked against `MAX_STREAM_BYTES`.

**Failure is loud, per the constraint.** On exceeding the ceiling the child's process group is
killed, the partial buffer is **discarded**, and a `BackendError` naming the limit and the stream is
raised. Nothing partial reaches a caller — silently returning truncated NDJSON would corrupt
descriptor values, which is worse than the exhaustion prevented.

### The constant, and its recorded rationale

```ruby
MAX_STREAM_BYTES = 32 * 1024 * 1024
STREAM_CHUNK_BYTES = 64 * 1024
```

Derived, not picked, and the derivation is in a comment on the constant: the widest stdout payload is
one NDJSON line per path carrying all nine descriptors, dominated by the 200-float embedding at
~4.5 KiB per path, so 32 MiB is ~7,000 paths per batch; measured Essentia stderr chatter of ~8 KiB per
path puts the same ceiling at ~4,000 paths. Callers analyze one path or a handful. **The bound cannot
bite legitimate output, which is the point — it stops unbounded growth, it is not a budget.**

### Stderr elision (second half of the issue)

`STDERR_MESSAGE_BYTES = 4 * 1024`, split head/tail, with an explicit marker naming the elided byte
count: `[... sonance elided N bytes of backend stderr ...]`. Head and tail are both kept because the
cause is the configuration error at the top or the traceback at the bottom; the middle is repeated
warning lines. Motivated by the measured 24,948-byte stderr that became a raised message verbatim.

### Happy path unchanged

Chunked reads produce the identical byte sequence for any output under the ceiling; an example
asserts a payload round-trips byte-for-byte. `git diff --stat d514137..HEAD -- lib/sonance/registry.rb python/`
is **empty** — no computed value changed.

### A real defect the specs caught mid-implementation

The first run failed with `Errno::EPERM` from `Process.kill("KILL", -pid)`: the child frequently
exits between crossing the ceiling and the kill, and a group whose leader has reaped answers `ESRCH`
or, on macOS, `EPERM`. `kill_group` now rescues both. This was found by the new spec, not by
inspection.

**Observation, not changed:** the pre-existing `terminate` (timeout path) rescues only `ESRCH` and has
the same exposure. I left it alone — it is unrelated to #6, its spec passes, and widening it would
touch pre-existing timeout behaviour this dispatch told me not to change. Worth a follow-up issue.

### Mutation battery — the gate, not the suite

Scope: `spec/backends/command_runner_spec.rb` + `spec/backends/essentia_python_spec.rb`.
Every mutation was applied to the committed tree and reverted with `git checkout --`.

| # | Mutation | Result |
|---|---|---|
| — | **CONTROL** (unmutated) | **29 examples, 0 failures** |
| M1 | Remove the bound entirely (revert to unbounded accumulation) | **4 failures** |
| M2′ | **Raise the ceiling past the fixture** (`limit * 100`), fixture left at 4 KiB | **4 failures** — `expected Sonance::BackendError ... but nothing was raised` |
| M3 | Silently truncate instead of raising (delete `raise_stream_limit!`) | **4 failures** |
| M4 | Remove the stderr elision call | **1 failure** |
| M5 | Change the shipped `MAX_STREAM_BYTES` (32 MiB → 1024) | **1 failure** |
| M6 | Lower the ceiling *below* the just-inside control (`limit - 1`) | **5 failures** |

Boundary coverage is both directions and both streams: exactly `limit` bytes **passes** (control just
inside), `limit + 1` **raises** (just outside), for stdout and for stderr independently. M6 exists to
prove the just-inside control is not vacuous — it fails when the ceiling moves under it.

**A mutation I got wrong, and am reporting rather than hiding.** My first M2 raised the spec's `limit`
let-binding to 32 MiB and the suite stayed green — because `limit` drives both the stubbed ceiling and
the fixture size, so raising it scaled the fixture too and tested nothing. That is exactly the
"gate that cannot fail" shape this repo has a history of. M2′ above is the corrected mutation: it
raises the *ceiling* while holding the fixture fixed, and it fails as required.

### Why bounds are exercised through `stub_const`

Writing 32 MiB twice per example to hit the real boundary is slow and adds nothing — the boundary
logic is identical at any ceiling. The examples stub `MAX_STREAM_BYTES` to 4096 and
`STREAM_CHUNK_BYTES` to 1024 so the boundary is hit exactly, and a separate example asserts the
**shipped** value independently. Without that second example the boundary tests would pass against
any constant, including none; M5 proves it bites.

---

## Verification

| Gate | Result |
|---|---|
| Full gem suite | **208 examples, 0 failures** (base was 194) |
| RuboCop | **45 files inspected, no offenses detected** |
| Bounded-read specs, 3 consecutive runs | 9/0, 9/0, 9/0 — no flake |
| `git diff --stat d514137..HEAD -- lib/sonance/registry.rb python/` | **empty** — no computed value changed |
| Brakeman | N/A — plain Ruby gem, not in the Gemfile, does not apply |

### No-conflict compliance — verified

Files changed across both commits:

```
lib/sonance/backends/essentia_python.rb
lib/sonance/value.rb
spec/backends/command_runner_spec.rb
spec/backends/essentia_python_spec.rb
spec/cli_spec.rb
spec/support/recording_cli_analyze.rb
spec/support/recording_cli_values.rb   (new)
```

**Zero overlap** with the forbidden set owned by `fix/pin-python-stack-and-notice-uris`
(`Dockerfile.essentia`, `constraints.txt`, `spec/support/canonical_essentia_environment.rb`,
`spec/canonical_essentia_environment_spec.rb`, `NOTICE`). Nothing I needed lived in those files, so I
did not have to stop and ask.

## RISK TRIGGERS TOUCHED

| Trigger | Touched | Detail |
|---|---|---|
| Runtime external integration | **YES (hardened)** | The subprocess boundary is the gem's one external integration. #6 bounds an unbounded input on it. Defence added, none removed. |
| Public API surface | **YES (additive)** | `Value#as_json` / `#to_json` are new public methods. Nothing removed or renamed; `exe/sonance` untouched. |
| Destructive op | NO | No deletions of tracked content. |
| Migration / authz / data exposure | NO | None. |
| New dependency | NO | None added. |
| External automation config | NO | No CI, Dockerfile, or deploy config touched. |

**Behaviour change worth flagging to review:** a backend that previously exhausted memory now raises
`Sonance::BackendError`. `BackendError` is a `FatalError`, so it aborts the batch rather than being a
per-track skip — correct, since a stream that large means the backend is malfunctioning, not that one
track is bad.

## Final state

- BASE_SHA: `d514137a09facf8c64519e189aed57c3abaf5635`
- Commit 1: `364b02816592f2a9c05355747a9df7b41f44ee43` (issue #5)
- Commit 2 / HEAD_SHA: `3f1f5110464e0a795481af6328d8506af1d5c499` (issue #6)
- Branch `fix/cli-output-and-bounded-subprocess-reads`, **not pushed**, no PR opened.
- Working tree clean apart from the pre-existing untracked `.worktrees/`.

# Review round 2 — LOW finding fixed

**Commit 3 / HEAD_SHA:** `1bc6552fd8a8983012f852887caa4d9856e60f31`
**Files:** `lib/sonance/backends/essentia_python.rb`, `lib/sonance/extractor.rb`. Comments and
documentation only — no behaviour change, no computed value change.

## 1. The claim was false, and worse than the finding assumed

I re-derived the numbers by measuring real Essentia rather than taking 7,600. The finding is correct
that the bound can bite. **It bites far earlier than either of us thought, because the binding stream
is stderr, not stdout, and stderr scales with audio duration rather than path count.**

Method: run the real extractor with all nine descriptors over N and 2N identical paths and take the
delta, which cancels fixed startup. Verified linear — the 1→2 and 2→4 deltas agree exactly.

| | measured | ceiling binds at |
|---|---|---|
| **stdout** | **4,513 B** for one full-precision nine-descriptor NDJSON line (85-byte path; features 4,188 B, of which the 200-float embedding is 3,830 B) | **~7,400 paths** |
| **stderr, 10 s fixtures** | **44,968 B/path** (fixed startup 1,801 B) | **~750 paths** |
| **stderr, 180 s track** | **832,447 B/path** | **~40 paths** |

So per-path stderr is ~4.6 KiB **per second of audio**. For 3-minute tracks the 32 MiB ceiling is
reached at roughly **40 paths — two or three albums**, not 7,600 paths.

My original ~4.5 KiB stdout estimate was accurate (4,513 measured vs Litmus's 4,398; the difference is
path-string length). What neither estimate caught is that stdout is not the stream that binds.

**argv is not the first limit, confirming the finding's ordering.** `getconf ARG_MAX` on this host is
1,048,576, about 12,300 paths at an 85-byte path — so the stream ceiling binds well before exec does.

### A measurement of mine that was wrong, and how I caught it

My first linearity check reported stderr flat at 1,596 bytes for 1/2/3/4 paths, contradicting the
delta measurement. It was the *measurement* that was broken — the loop built its file list with
`ls | head -N`, which did not vary the input the way I intended. I did not average the two or pick the
convenient one; I re-measured explicitly with the same file repeated N times, got perfect linearity
(46,769 → 91,737 → 181,673, deltas 44,968 and 44,968), and discarded the bad run. Recording it because
a contradiction between two of my own measurements is exactly the moment to stop and re-derive.

## 2. What I changed, and what I did not

**Corrected** the `MAX_STREAM_BYTES` comment to state plainly that the bound *can* be reached by
legitimate output, with the per-stream figures, the duration scaling, and both binding path counts.
It no longer asserts anything it cannot support.

**Documented chunking** on `Extractor#analyze_all` with a worked `each_slice(25)` example and the
binding path counts.

**Did not chunk internally.** Reasons: the right slice size depends on track duration and on how the
caller wants a mid-batch failure handled — neither is knowable in the gem; every chunk pays the
backend's process and model-load startup again, which is seconds, not milliseconds; and it changes a
public API's execution model, which is a behaviour change deserving its own issue and review rather
than riding along on a comment fix. vibe-doctor is unaffected either way — it calls `analyze` one path
at a time.

**Added the portability note** where the rescue lives: Linux answers ESRCH where macOS answers EPERM,
so simplifying `kill_group` to ESRCH alone stays green on Linux CI and reintroduces the bug on macOS.

## 3. ESCALATION — the ceiling is arguably mis-sized, and I did not unilaterally re-engineer it

At ~40 paths for real tracks, this guard fires during ordinary use. I deliberately stopped at
documenting it, but the root cause is worth a decision:

> **stderr is retained whole in memory only to be elided to `STDERR_MESSAGE_BYTES` (4 KiB) the moment
> it is used.** We buffer up to 832 KB per track of repeated `[ WARNING ] No network created...` text
> and then throw essentially all of it away. Retaining only a head and a tail as we drain would make
> stderr O(4 KiB) regardless of stream size, remove it as the binding stream entirely, and produce a
> byte-identical error message — because the message already keeps only head and tail.
>
> stdout must keep its hard ceiling: it is the protocol payload and truncating it would corrupt values.

That is a real behaviour change — a huge stderr would stop failing the batch, which I believe is
correct, since stderr volume is Essentia being chatty, not an error. **I did not implement it**: it is
beyond this dispatch, and the finding as filed asked for a comment correction. Recommend filing it
against #6 or as a successor. Happy to take it as its own commit with its own mutation evidence.

## 4. The 194 → 208 count was not purely additive — correcting my own report

Litmus is right and my round-1 report understated this. Verified by execution:

```
$ git show d514137:spec/cli_spec.rb | grep -o 'it "[^"]*"'
it "requires --descriptors for analyze"
it "passes comma-separated descriptor ids to analyze"      <- REMOVED at HEAD
it "prints available descriptor ids"
```

**One named pre-existing example was removed**, not merely added to: `194 - 1 + 15 = 208`. It asserted
on stub-shaped output (`{"path" => ..., "descriptors" => [...]}`) that no longer exists once the stub
returns a real `Analysis`, so it could not survive the blindness fix in its original form.

**Its coverage does survive**, and I confirmed that independently rather than accepting the claim:
dropping the `Array` coercion from `OptionParser` at `exe/sonance:34` produces **4 failures** in the
new examples (restored immediately; tree verified clean). The comma-separated parse is now asserted
through the emitted JSON keys instead of through a stub's echo.

A named example disappearing should never be silent, and it was silent in my round-1 report. Noted.

## Verification (round 2)

| Gate | Result |
|---|---|
| Full gem suite | **208 examples, 0 failures** |
| RuboCop | **45 files inspected, no offenses detected** |
| `git diff --stat d514137..HEAD -- lib/sonance/registry.rb python/` | **empty** — no computed value changed |
| Forbidden-file overlap | **none** — touched files listed below |
| Internal chunking | not implemented, so no mutation evidence required |

Files changed across all three commits:
`lib/sonance/backends/essentia_python.rb`, `lib/sonance/extractor.rb`, `lib/sonance/value.rb`,
`spec/backends/command_runner_spec.rb`, `spec/backends/essentia_python_spec.rb`, `spec/cli_spec.rb`,
`spec/support/recording_cli_analyze.rb`, `spec/support/recording_cli_values.rb`.
Still zero overlap with `Dockerfile.essentia`, `constraints.txt`,
`spec/support/canonical_essentia_environment.rb`, `spec/canonical_essentia_environment_spec.rb`,
`NOTICE`.

## Final state

- BASE_SHA: `d514137a09facf8c64519e189aed57c3abaf5635`
- Commit 1: `364b02816592f2a9c05355747a9df7b41f44ee43` (issue #5)
- Commit 2: `3f1f5110464e0a795481af6328d8506af1d5c499` (issue #6)
- Commit 3 / HEAD_SHA: `1bc6552fd8a8983012f852887caa4d9856e60f31` (review finding)
- Branch `fix/cli-output-and-bounded-subprocess-reads`, **not pushed**, no PR.
- `terminate()` EPERM exposure left untouched as instructed; you are filing it separately.

## RISK TRIGGERS TOUCHED (round 2)

None beyond round 1. Commit 3 is comments and YARD documentation only — no runtime code path changed,
no constant value changed, no public method added or removed.
