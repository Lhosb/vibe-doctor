## Problem

The 32 MiB stream ceiling added in #6 is correct and must stay. But **stderr, not stdout, is the
binding stream**, and it binds far earlier than anyone estimated.

Measured against real Essentia, N vs 2N identical paths so fixed startup cancels, linearity
verified:

| Stream | Bytes per path | Binds at |
|---|---:|---:|
| stdout — full-precision nine-descriptor NDJSON line | 4,513 | ~7,400 paths |
| stderr — 10 s fixtures | 44,968 | ~750 paths |
| stderr — 180 s track | 832,447 | **~40 paths** |

**Per-path stderr scales with audio duration**, roughly 4.6 KiB per second of audio — not with
path count. For ordinary 3-minute tracks the ceiling is reached at about **forty paths**. Two or
three albums.

Two independent estimates during review put the limit at ~7,400–7,600 paths. Both were accurate
*for stdout*, and both were measuring the wrong stream.

`ARG_MAX` is 1,048,576 here, about 12,300 paths at an 85-byte path, so the stream ceiling still
binds first.

## Root cause

**stderr is retained whole only to be elided to 4 KiB the moment it is used.**

The runner buffers up to 832 KB per track of repeated "No network created" chatter, then throws
essentially all of it away — the error message already keeps only a head and a tail.

## Proposed fix

Retain only a head and a tail **while draining**, rather than buffering the whole stream and
eliding at the end.

- stderr becomes **O(4 KiB) regardless of stream size**, removing it as the binding stream
  entirely.
- The error message is **byte-identical**, because it already keeps only head and tail.
- **stdout keeps its hard ceiling** — it is the protocol payload and truncating it would corrupt
  values. Do not weaken it.

This is a real behaviour change: a huge stderr would stop failing the batch. That is believed
correct — large stderr volume is Essentia being chatty, not an error condition — but it needs its
own mutation evidence rather than riding along on a comment fix.

## Scope note

`vibe-doctor` is **unaffected either way**: it calls `analyze` one path at a time and never uses
`analyze_all`. This is a gem-API problem, not an app deploy blocker.

Internal chunking of `analyze_all` was considered and deliberately rejected as the fix: the right
slice size depends on track duration and on how a mid-batch failure should be handled, neither
knowable inside the gem; every chunk re-pays process and model-load startup, seconds not
milliseconds; and it changes a public API's execution model. Chunking is now documented on
`Extractor#analyze_all` with a worked `each_slice(25)` example for callers who need it today.

## Provenance

Found while correcting an over-broad comment claim during the #6 review, 2026-08-14. The
implementer re-derived the numbers rather than accepting the reviewer's figure, which is how the
wrong-stream error surfaced.

Worth recording: the implementer's first linearity check reported stderr flat at 1,596 bytes and
contradicted its own delta measurement. The loop was broken — it built its file list with
`ls | head` and never varied the input. It re-measured with the same file repeated N times, got
46,769 → 91,737 → 181,673 with deltas of exactly 44,968, and **discarded the bad run rather than
averaging the two or taking the convenient one.** A contradiction between two of your own
measurements is exactly when to stop and re-derive.
