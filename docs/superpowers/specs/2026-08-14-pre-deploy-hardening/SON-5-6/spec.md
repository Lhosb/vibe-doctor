# SPEC REVIEW — sonance #5 and #6 (Tier 2) — requirement conformance

**VERDICT: APPROVE.** Both issues are satisfied as written, including each issue's literal
verification clause. Nothing in the diff is outside what the issues asked for. Three observations,
none blocking — and one of them **corrects the premise of your question 5**.

- REPO: `/Users/lukeolson/projects/gems/mood_probe` (gem/module/repo all `sonance`; dir name stale)
- BASE: `d514137a09facf8c64519e189aed57c3abaf5635`
- HEAD: `1bc6552fd8a8983012f852887caa4d9856e60f31` — branch tip confirmed == HEAD, stable
- Commits: `364b028` (#5), `3f1f511` (#6), `1bc6552` (review fixes)
- Full suite at HEAD: **208 examples, 0 failures** (base was 194)
- Not re-litigated: the nine mutation batteries (Litmus, settled). The 40-path ceiling itself
  (sonance #22) — but I did check the comment describing it, as instructed.

---

## 1. #5 FIXED AT THE VALUE LAYER WITH `exe/sonance` UNCHANGED — IN SCOPE. DECIDED.

**Within scope, and not a broader change than asked.** The issue's own Required-work section offers
exactly this as its first option:

> - Give `Value` (and subclasses) a real JSON representation, **or** serialize explicitly in the CLI.

The Value layer is not an expansive reading — it is option one of two the issue itself put on the
table. The argument the other way would be that a CLI bug deserves a CLI fix, and that touching the
public API to fix one call site is disproportionate. I do not find that persuasive here, for a reason
internal to the issue: its **Verification** clause reads

> the spec must fail if `Value#to_json` is removed

That clause **presupposes `Value#to_json` exists.** The issue does not merely permit the Value-layer
fix; it anticipates it and writes its acceptance test against it. A CLI-only fix would have left that
verification clause unsatisfiable as written. So the implementer picked the option the issue's own
acceptance criterion was written for.

**On the API-surface trigger the implementer flagged:** correct to flag, and the flag is the right
disposition. `Value#as_json` and `Value#to_json` are genuinely new public methods on a public class,
inherited by all four subclasses — the gem's API is additively larger. That is a real consequence,
but it is the consequence the issue chose. Base-class `as_json` raises `NotImplementedError`
(`value.rb:47-49`), so a third-party `Value` subclass gets a clear failure rather than silently
re-inheriting the inspect-string bug. That is the right default.

**Serializing all four kinds is also in scope**, not over-reach: the issue says "`Value` **(and
subclasses)**". `Categorical` and `Series` are not produced by the default registry, but they are
reachable through a custom registry — which the README documents as supported — and without their
`as_json` they would hit the `NotImplementedError`. Covering them is what the issue asked for.

---

## 2. THE SPEC BLINDNESS — GENUINELY CLOSED, NOT RELOCATED

This is the finding I raised as H2 in the main audit, so I checked it hard.

**What made the old stub blind:** `recording_cli_analyze.rb:5` replaced `Extractor#analyze` with a
`Data.define(:path, :descriptors)` — a JSON-native object. The only object that reproduces the
defect is the `Analysis` the stub replaced, so the spec could not observe it no matter what it
asserted.

**What the new stub does differently** (`recording_cli_analyze.rb:14-26`): it replaces the *backend*,
not the *result type*. It returns a real `Analysis`, of real `Value` objects, built through the real
`AnalysisBuilder`, against the real `Registry.default`. The production serialization path is the path
under test. `Value` construction runs its real validations, because the payload table
(`recording_cli_values.rb:11-21`) uses values inside each descriptor's declared range.

**Where blindness could have relocated, and why it did not.** The residual risk in any table-driven
stub is that it only proves what the table happens to contain — a descriptor absent from the table is
untested, and nothing says so. That is precisely the failure mode I flagged on VD-24. It is closed
here by an explicit non-vacuity floor, `cli_spec.rb:72-76`:

```ruby
expect(RecordingCliValues::RAW_VALUES.keys).to match_array(Sonance::Registry.default.ids)
```

Add a descriptor to the registry without adding a payload, and that example fails. The comment above
it states the reason in exactly those terms.

Two further properties worth crediting, because they are the ones usually lost:

- **Distinct values per descriptor** (`4.5, 6.25, 0.75, 0.125, 0.5, 0.875, <array>, 123.5, 3.25`),
  with a comment saying why: a shared placeholder would hide a descriptor mix-up. This is the
  head-independence property that a "simplify the fixture" refactor typically deletes.
- **The suite-wide leak was caught and fixed.** Requiring the stub from the main RSpec process
  monkey-patches `Sonance::Extractor` for every other spec; the implementer found this by execution
  (`extractor_spec` alone 9/0, `cli_spec`-then-`extractor_spec` 9 failures) and split the payload
  table into its own file so the coverage example can load the table without the patch. The stub
  reaches the CLI only via `RUBYOPT`.

**What remains unobservable, correctly:** `Extractor#analyze`'s own behaviour is stubbed out, so the
CLI spec cannot see a defect there. That is `extractor_spec`'s job, not this spec's, and the split is
right.

**Verdict on Q2: closed.** The blindness is not relocated; the one place it could have relocated to
is guarded by an assertion that fails loudly.

---

## 3. THE FORMAT CHOICE — DEFENSIBLE, AND THE ROUND-TRIP IS ASSERTED, NOT MERELY DESCRIBED

**It is asserted.** `cli_spec.rb:55-67`, "renders output the analysis builder can rebuild without
translation", parses CLI stdout and feeds it straight into a real `AnalysisBuilder`:

```ruby
rebuilt = Sonance::AnalysisBuilder.new(registry: Sonance::Registry.default).call(
  requested: descriptors, raw_values: JSON.parse(stdout)
)
expect(rebuilt[:bpm_rhythm2013].value).to eq(123.5)
expect(rebuilt[:embedding_musicnn].values.length).to eq(200)
```

This is a real executable round-trip over both a scalar and a vector, not prose. Had it been
described only in a comment I would have called that out; it is not.

**It satisfies the issue's stated verification literally.** The issue's command is
`analyze <fixture> --descriptors bpm_rhythm2013`, and its criterion is "parseable JSON whose values
are numbers". I ran it:

```
$ ruby -Ilib exe/sonance --models-dir /tmp/nonexistent \
    --descriptors bpm_rhythm2013,beat_confidence_rhythm2013 analyze spec/fixtures/sonance/audio/sine_440.wav
{
  "bpm_rhythm2013": 110.60472869873047,
  "beat_confidence_rhythm2013": 2.2199807167053223
}
exit=0
```

Real audio, real backend, no stub. `110.60472869873047` is the exact value I had to recover through
the library API in the main audit to prove the CLI was dropping it. The defect is gone at the
documented entry point.

**The choice is defensible.** The strongest argument for it is that it is *not a new format*:
`sonance_extract.py` already emits `{"features": {"<id>": <value>}}` with bare numbers for scalars
and arrays for vectors, and `AnalysisBuilder` already consumes exactly that. CLI stdout and backend
stdout are now the same shape, so there is one wire format in the system rather than two. Rejecting a
richer `kind`/`units`/`provenance` object is consistent with that: it would be a shape nothing else
in the library speaks, and it would break the round-trip property the spec now pins.

**The one real cost**, which I note rather than fault: a CLI-only consumer cannot tell from stdout
alone that `0.75` is a probability and `123.5` is BPM. Units and kind are reachable through the
library API and through the registry, and issue #5 asked only for numbers — so this is a
consequence of the issue's own framing, not a shortfall against it. Worth recording in case a future
issue wants a `--format rich`.

---

## 4. #6 BOUNDED READS — FAILS LOUDLY, PARTIAL DISCARDED. VERIFIED BY MY OWN EXECUTION.

All three Required-work items are delivered:

| #6 requirement | Where | Verified |
|---|---|---|
| bound both reads with an explicit maximum | `MAX_STREAM_BYTES = 32 MiB`, applied to both readers | ✓ |
| on exceeding, terminate the subprocess and raise `BackendError` naming the limit, not truncate silently | `kill_group` + `raise_stream_limit!` | ✓ |
| truncate stderr before it becomes an exception message, head and tail with an explicit elision marker | `truncate_stderr` | ✓ |

**The discard is structural, not incidental.** `bounded_reader` breaks out with a partial buffer, but
`capture` raises *before* returning `captured`:

```ruby
captured = pump(...)                                   # partial buffer lives here
raise_stream_limit!(overflowed.first) unless overflowed.empty?
captured
```

A method cannot both raise and return, so no truncated stream can reach a caller. I did not take that
on reading — I drove it directly with the ceiling stubbed to 4096:

```
CONTROL exactly 4096 B  -> RETURNED Result: stdout=4096B exit=0
4097 B                  -> RAISED BackendError: ... exceeded the 4096 byte stdout limit; the
                           subprocess was terminated and its output discarded
400 KB                  -> RAISED (no partial returned)
stderr 4097 B           -> RAISED, names stderr
infinite writer         -> RAISED in 0.03s   (timeout was 10s, so the kill worked)
```

The 0.03s on the runaway case is the load-bearing one: it proves termination, not merely that the
read stopped — without the kill it would have sat until the 10s timeout.

**The specs carry non-vacuity floors on both axes**, which is why I am comfortable with the stubbed
constant: `command_runner_spec.rb` asserts the *shipped* value is 32 MiB independently of the stubbed
examples, and pairs "accepts exactly the limit" (passing control) with "one byte past it" (failing).
Boundary tests with a passing control on the inside — exactly right.

**The stderr elision** keeps head and tail with `[... sonance elided N bytes of backend stderr ...]`
and is specced in both directions (over the ceiling elides and preserves head+tail; under it is left
byte-identical).

---

## 5. THE CONSUMER-VISIBLE CHANGE — I AGREE WITH THE CLASSIFICATION. **BUT YOUR PREMISE NEEDS CORRECTING.**

### The premise: "vibe-doctor rescues `TrackError`, not `FatalError`" — true, but it cannot bite

**vibe-doctor never calls `analyze_all`.** It calls `analyze` — singular — once per track, at
`app/services/mood_grounding_service.rb:114` and `:127`. `Extractor#analyze` wraps a **single** path
(`extractor.rb:62-67`, `analyze_all([path], …)`), so vibe-doctor gets **one subprocess and one stream
pair per track**. Streams never accumulate across tracks there.

So the batch-abort scenario is real in the API but **unreachable for vibe-doctor as written**:

```
one 180 s track: 832,447 B = 2.5% of the 33,554,432 B ceiling
audio needed to hit the ceiling in ONE analyze call: 7,255 s = 2.0 hours
```

For vibe-doctor to see this `BackendError` it would need a single ~2-hour track, or a genuinely
malfunctioning backend. The "40 paths of 3-minute tracks" figure — correct as it is — applies only to
a caller that batches through `analyze_all`, and vibe-doctor is not one.

### On the classification itself: agree, and for a stronger reason than the one given

The implementer's stated justification is "a 32 MiB stream means the backend is malfunctioning, not
that one track is bad." **That reason is only partly sound, and the code comment at HEAD says so** —
it states plainly that the ceiling "CAN be reached by legitimate output". For a batching caller,
32 MiB of stderr is ordinary Essentia chatter, not malfunction. So the stated reason does not carry
the argument.

Two better reasons do, and they are decisive:

1. **The overflow cannot be attributed to a track.** One subprocess serves the whole batch and both
   streams are shared, so a `TrackError` would have to name a track the runner cannot identify.
   Attributing it to one track would be *wrong*, not merely conservative.
2. **There is no per-track data to salvage.** The partial buffer is deliberately discarded, and the
   subprocess is killed. There is no remaining state from which per-track results could be produced,
   and nothing left to continue the batch with. "Skip this track and carry on" is not an available
   outcome.

`FatalError` means "this run", `TrackError` means "this track". A killed subprocess with its output
thrown away is unambiguously this run. **`BackendError` is the correct class.**

Worth stating plainly for the deploy record: this is strictly an improvement on what it replaces. The
prior behaviour on a runaway backend was unbounded accumulation ending in an OOM kill — also fatal,
but silent and misattributed. The new failure is loud, named, and points at the limit.

---

## 6. ANYTHING NOT REQUIRED BY EITHER ISSUE

Nothing that I would call out of scope. Every file maps to a requirement:

| File | Issue | Required? |
|---|---|---|
| `lib/sonance/value.rb` | #5 | yes — "give `Value` (and subclasses) a real JSON representation" |
| `spec/cli_spec.rb`, `spec/support/recording_cli_analyze.rb` | #5 | yes — "replace the stub", "assert on the actual emitted JSON payload" |
| `spec/support/recording_cli_values.rb` (new) | #5 | yes — required by the leak fix and by the non-vacuity floor |
| `lib/sonance/backends/essentia_python.rb` | #6 | yes — all three required items |
| `spec/backends/command_runner_spec.rb`, `spec/backends/essentia_python_spec.rb` | #6 | yes |
| `lib/sonance/extractor.rb` (+13, YARD only) | — | **not literally required — see O1** |

**`exe/sonance` is unchanged**, confirmed: it is absent from the diff entirely.

---

## OBSERVATIONS (none blocking)

### O1 — `extractor.rb` YARD chunking guidance is not literally required by either issue

`lib/sonance/extractor.rb:71-81` adds documentation-only YARD describing the `MAX_STREAM_BYTES`
interaction and recommending `paths.each_slice(25)`. Neither issue asks for it.

**I am not treating it as scope creep.** #6 introduces a new way for a legitimate large batch to
fail, and documenting that on the method that causes it is part of landing the change responsibly —
shipping the ceiling without telling `analyze_all` callers it exists would be the worse choice. It is
documentation, adds no behaviour, and the numbers in it are correct (checked below). Noted only so
the line count has an owner.

### O2 — one figure in the comment is ~2–5% optimistic; the load-bearing numbers are exact

You asked me to check the comment is true, since a false comment started this. **The path counts are
all correct**, recomputed from the shipped constant:

| Comment claim | Recomputed | |
|---|---|---|
| stdout 4,513 B/path → "roughly 7,400 paths" | 7,435 | ✓ |
| stderr 44,968 B/path (10 s) → "roughly 750 paths" | 746 | ✓ |
| stderr 832,447 B/path (180 s) → "roughly 40 paths" | 40 | ✓ |
| "roughly 4.6 KiB per second of audio" | 4.39 KiB/s (10 s) and 4.52 KiB/s (180 s) | slightly high |

The per-second rate is stated as ~4.6 KiB/s where the two measurements give 4.39 and 4.52. That is a
rounding-up of a figure the comment itself calls "roughly", and nothing is derived from it — the path
counts come from the per-path bytes, which are exact. Not a finding; recorded because you asked for
the comment to be checked and this is the only imprecision in it. Both comments
(`essentia_python.rb:40-41` and `extractor.rb:74-75`) agree on 750 and 40.

### O3 — the `analyze_all` documentation is written for a caller that does not currently exist

Following from Q5: the chunking guidance addresses `analyze_all` callers, and the gem's only known
consumer uses `analyze`. That is fine — the gem is public and the guidance is correct — but if the
`analyze_all`/`analyze` split matters to the deploy story, the fact that **vibe-doctor is on the
per-track path and therefore unexposed** is the more useful thing to record on #22 than the 40-path
figure alone.

---

## WHAT I DID NOT VERIFY

- **The nine mutation batteries** — excluded by dispatch; Litmus re-ran them from fresh `git archive`
  extractions and every count matched.
- **The measured byte figures themselves** (4,513 / 44,968 / 832,447 B per path). These came from
  real-Essentia runs I cannot reproduce here — the golden path needs `linux/amd64`. I verified every
  arithmetic consequence *derived* from them, and that the constants in code match the comment, but
  the raw measurements are the implementer's.
- **The rebase onto `5647a12`** — explicitly not my problem per dispatch, and I did not attempt it.
- **macOS-vs-Linux `kill_group` portability** (the `EPERM` rescue at `essentia_python.rb`): the
  comment reports a 10/10 mutation result. I ran on macOS only and my runaway-writer probe passed, so
  the macOS half is consistent with the claim; I did not test Linux.

---

## EVIDENCE

Read-only throughout. No repo mutation; the ceiling probe redefined constants in a **separate
`ruby -e` process**, not in the working tree.

### State

```
$ git rev-parse HEAD fix/cli-output-and-bounded-subprocess-reads
1bc6552fd8a8983012f852887caa4d9856e60f31
1bc6552fd8a8983012f852887caa4d9856e60f31     <- stable

$ git log --oneline d514137..1bc6552
1bc6552 Correct the stream-ceiling claim and document batch chunking (issue #6 review)
3f1f511 Bound subprocess stdout and stderr reads (issue #6)
364b028 Serialize descriptor values as JSON and let the CLI spec observe it (issue #5)

$ bundle exec rspec
208 examples, 0 failures                      (base d514137 was 194)
```

`exe/sonance` absent from `git diff --stat d514137 1bc6552` — 8 files, none of them the executable.

### #5 — the documented command, real backend, real audio

```
$ ruby -Ilib exe/sonance --models-dir /tmp/nonexistent \
    --descriptors bpm_rhythm2013,beat_confidence_rhythm2013 analyze spec/fixtures/sonance/audio/sine_440.wav
{
  "bpm_rhythm2013": 110.60472869873047,
  "beat_confidence_rhythm2013": 2.2199807167053223
}
exit=0
```

Compare the main-audit reproduction at base: `"bpm_rhythm2013": "#<Sonance::Scalar:0x000000011ff3f9d8>"`.

Vector rendering, via the stub:

```
$ RUBYOPT="-Ispec/support -rrecording_cli_analyze" ruby -Ilib exe/sonance \
    --descriptors bpm_rhythm2013,embedding_musicnn analyze track.wav
{
  "bpm_rhythm2013": 123.5,
  "embedding_musicnn": [
    0.001,
    0.002,
    ...
```

### #6 — bounded reads, driven directly with the ceiling at 4096

```
=== CONTROL: exactly at the 4096 limit must SUCCEED and return all bytes ===
stdout 4096          RETURNED Result: stdout=4096B stderr=0B exit=0

=== one byte past ===
stdout 4097          RAISED BackendError: Essentia backend exceeded the 4096 byte stdout limit;
                     the subprocess was terminated and its output discarded

=== massively past: is ANY partial data returned? ===
stdout 400KB         RAISED BackendError: ... output discarded

=== stderr past the limit ===
stderr 4097          RAISED BackendError: ... exceeded the 4096 byte stderr limit ...

=== runaway writer: does it terminate promptly? ===
infinite stdout loop RAISED BackendError: ... exceeded the 4096 byte stdout limit ...
                     elapsed 0.03s (timeout was 10s, so a prompt raise proves the kill worked)
```

### Comment arithmetic

```
MAX_STREAM_BYTES = 33554432 bytes (32 MiB)
  stdout 4,513 B/path             -> binds at 7435 paths      (comment: "roughly 7,400")
  stderr 44,968 B/path (10s)      -> binds at 746 paths       (comment: "roughly 750")
  stderr 832,447 B/path (180s)    -> binds at 40 paths        (comment: "roughly 40")
per-second: 10s fixture 4.39 KiB/s ; 180s track 4.52 KiB/s    (comment: "roughly 4.6")
```

Shipped constants match the comment: `MAX_STREAM_BYTES = 32 * 1024 * 1024`,
`STREAM_CHUNK_BYTES = 64 * 1024`, `STDERR_MESSAGE_BYTES = 4 * 1024`.

### Q5 — vibe-doctor's call shape

```
app/services/mood_grounding_service.rb:114:  @feature_extractor.analyze(dest_path,  descriptors: …)
app/services/mood_grounding_service.rb:127:  @feature_extractor.analyze(clip_path,  descriptors: …)
                                             ^ analyze, singular — no analyze_all anywhere

lib/sonance/extractor.rb:62-63
    def analyze(path, descriptors:)
      result = analyze_all([path], descriptors:).first     <- one path per subprocess

one 180s track: 832,447 B = 2.5% of the 33,554,432 B ceiling
audio needed to hit the ceiling in ONE analyze call: 7,255 s = 2.0 hours
```

### Repo state

Read-only. No edits, no commits, no staging, nothing pushed. Both repositories remain on their
current branches; the ceiling probe ran in a throwaway `ruby -e` process.

---

## SUMMARY

**APPROVE.** #5 and #6 are each satisfied as written, including both literal verification clauses.
Nothing is out of scope.

- **Q1** — Value-layer fix is **in scope**: it is option one in the issue's Required work, and the
  issue's acceptance criterion ("must fail if `Value#to_json` is removed") presupposes it.
- **Q2** — blindness **closed**, not relocated; the one place it could relocate to is guarded by an
  explicit registry-coverage floor.
- **Q3** — format defensible (it is the library's existing wire format, not a new one), and the
  round-trip is **asserted by `cli_spec.rb:55-67`**, not merely described.
- **Q4** — **loud and discarding**, verified by my own execution including a passing control at the
  boundary and a 0.03s kill on a runaway writer.
- **Q5** — **agree** `BackendError` is correct, but on the two reasons that actually hold
  (unattributable to a track; no data to salvage), not on the "backend is malfunctioning" reason,
  which the code comment itself contradicts. **And the premise cannot bite vibe-doctor**, which calls
  `analyze` per track and sits at 2.5% of the ceiling.
- **Q6** — nothing out of scope; `extractor.rb`'s YARD is the only non-literally-required line count
  and it is justified documentation of #6's consequence.
