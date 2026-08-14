# SON-5 / #6 — Test & Gate Review (test/gate discipline)

# VERDICT: **APPROVE**

Both mutation batteries reproduce **exactly** the claimed counts — I re-ran all nine mutations myself
from fresh `git archive` extractions. Both self-reported failures are real, correctly fixed, and
**gated**. The two mutations the dispatch cared most about — **M6** (non-vacuity floor for the passing
control) and **#5's M2** (proves the specs need a real `Analysis`) — both bite hard.

One **LOW** finding: a comment overstates that the bound "cannot bite legitimate output." It can, via
the public `analyze_all` batch API, at ~7,600 paths. Loud and non-corrupting, so not a blocker.

One thing I must report about my own work: I chased an intermittent
`1 error occurred outside of examples` for several rounds. **It was my shell-quoting bug, not a spec
defect.** Details in §7 so nobody else chases it.

Range: `d514137..3f1f511`. Commits `364b028` (#5), `3f1f511` (#6). Branch not pushed; `origin/main` has
since moved to `5647a12`, so a rebase is pending but out of scope.

---

## 1. Controls — all three match the report

```
$ bundle exec rspec                                              -> 208 examples, 0 failures
$ bundle exec rspec spec/backends/command_runner_spec.rb \
                    spec/backends/essentia_python_spec.rb        ->  29 examples, 0 failures
$ bundle exec rspec spec/cli_spec.rb                             ->   7 examples, 0 failures
```

Protected paths untouched, verified independently:
`git diff --stat d514137 3f1f511 -- lib/sonance/registry.rb python/` → **empty**. No computed value changed.

---

## 2. Issue #6 battery — re-run, not trusted

Each mutation applied to a **fresh** `git archive 3f1f511` extraction, with the harness aborting if an
anchor is missing so a mutation can never silently no-op.

| # | Mutation | Claimed | **Observed** | Failing examples |
|---|---|---|---|---|
| — | control | 29/0 | **29/0** | — |
| M1 | remove the bound (never stop accumulating) | 4 | **4** | stdout+stderr `limit+1`, discards-partial, terminates-runaway |
| M2′ | **raise the CEILING past a FIXED fixture** (`limit * 100`) | 4 | **4** | same four |
| M3 | silently truncate instead of raising | 4 | **4** | same four |
| M4 | remove stderr elision | 1 | **1** | `ep:192` elides the middle of an oversized stderr |
| M5 | change the shipped constant (32 MiB → 1024) | 1 | **1** | `cr:98` ships a stream ceiling large enough… |
| M6 | **lower the ceiling BELOW the just-inside control** (`limit - 1`) | 5 | **5** | see below |

### M6 — the non-vacuity floor, and it holds on both streams

```
rspec 'cr[1:2:1]' :: accepts stdout of exactly the limit      <- passing control FAILS
rspec 'cr[1:2:3]' :: accepts stderr of exactly the limit      <- passing control FAILS
rspec 'cr[1:2:2]' :: raises a BackendError … stdout one byte past it
rspec 'cr[1:2:4]' :: raises a BackendError … stderr one byte past it
rspec cr:73       :: terminates a subprocess that keeps writing after the limit
```

This is the check that matters: the two *exactly-at-limit passes* examples go **red** when the ceiling
moves under them, on **stdout and stderr independently**. The passing controls are therefore not
vacuous — they genuinely depend on the ceiling rather than passing because nothing is asserted.

### M2′ — confirmed genuinely fixture-independent

The self-reported bad M2 raised `let(:limit) { 4096 }`, which drives **both** the stubbed ceiling and
the fixture size, so it scaled the fixture too and tested nothing. I verified M2′ does not repeat that:
it edits **only** the ceiling —

```ruby
stub_const("#{described_class}::MAX_STREAM_BYTES", limit * 100)   # ceiling raised
```

— while `write_bytes(limit)`, `write_bytes(limit + 1)` and `write_bytes(limit * 4)` all still use the
**unchanged** `limit` of 4096. The fixture is held fixed and the ceiling alone moves. It produces 4
failures, the first being
`expected Sonance::BackendError … but nothing was raised`. **The correction is sound.**

(For the record I predicted 3 failures and was wrong — the runaway-writer example also fails at a 100×
ceiling. The implementer's 4 is correct.)

---

## 3. Issue #5 battery — re-run

| # | Mutation | Claimed | **Observed** | Failing examples |
|---|---|---|---|---|
| — | control | 7/0 | **7/0** | — |
| M1 | delete `Value#to_json` (the removal issue #5 names) | 4 | **4** | `cli:16`, `cli:32`, `cli:44`, `cli:55` |
| M2 | revert the stub to the old JSON-native `Data` object | 4 | **4** | same four |

**M2 is the load-bearing one and it bites.** Reverting the stub to
`Data.define(:path, :descriptors)` fails four examples — proving the new specs genuinely depend on a
real `Analysis` of real `Value` objects built through the real `AnalysisBuilder`, and would **not**
pass against the structural blindness that hid this defect for two releases. That was the single most
important thing to confirm here, and it is confirmed.

The fifth new example (the payload-table coverage floor) correctly does **not** fail under either
mutation — it asserts table coverage, not serialization. That is the right separation, not a gap.

---

## 4. The two self-reported failures — both verified

### (1) The bad M2 → M2′ correction: **CONFIRMED**, §2 above.

### (2) `Errno::EPERM` vs `ESRCH`: **CONFIRMED, and covered**

Shipped fix (`essentia_python.rb:125-128`):

```ruby
def kill_group(wait_thread)
  Process.kill("KILL", -wait_thread.pid)
rescue Errno::ESRCH, Errno::EPERM
  nil
end
```

Both are handled. And the dispatch asked whether a spec *actually covers* it — I tested by dropping
`Errno::EPERM` from the rescue and running 10 times, because the underlying race is nondeterministic:

```
run 1: 2 failures   run 2: 2   run 3: 2   run 4: 1   run 5: 1
run 6: 1            run 7: 1   run 8: 2   run 9: 2   run 10: 2
runs with failures: 10 / 10
```

**Reliably caught — 10/10.** The count varies (1–2) because the race decides which examples trip,
which is exactly the nondeterminism the fix exists for, but it never passes. The branch is genuinely
gated.

**Portability note, not a finding:** this coverage is platform-dependent. Linux answers `ESRCH` where
macOS answers `EPERM`, so on Linux CI dropping `EPERM` would likely *not* fail. The rescue is correct
and necessary; its *coverage* just may not reproduce on the CI runner. Worth knowing before anyone
"simplifies" it based on a green Linux run.

**The disclosed pre-existing exposure is accurate.** `terminate` rescues only `ESRCH`
(`essentia_python.rb:144-152`), and I confirmed it is byte-identical at base `d514137:66-72`. Genuinely
pre-existing, genuinely out of scope for #6, and correctly left alone. A follow-up issue is the right
call.

---

## 5. Boundary: both directions, both streams — **confirmed**

Four examples, generated by a `{ "STDOUT" => "stdout", "STDERR" => "stderr" }` loop:

| Stream | at exactly the limit | at limit + 1 |
|---|---|---|
| stdout | `accepts stdout of exactly the limit` — passes | `raises a BackendError naming the limit for stdout` |
| stderr | `accepts stderr of exactly the limit` — passes | `raises a BackendError naming the limit for stderr` |

Both sides on both streams, and M6 proves the *inside* side is non-vacuous while M1/M2′/M3 prove the
*outside* side is. That is a complete bound, not half of one.

The `limit + 1` assertion also matches on the message (`/exceeded the #{limit} byte #{name} limit.*
terminated and its output discarded/m`), so it cannot be satisfied by an unrelated `BackendError`.

---

## 6. The 32 MiB constant — derivation is sound, one claim overstated

### The derivation checks out

I measured a realistic widest NDJSON line — all nine descriptors including the 200-float embedding at
**full float64 precision** (my first attempt used the round fixture values and understated it at 1.45
KiB; that measurement was wrong, not the comment):

```
embedding_musicnn alone : 3956 bytes (3.86 KiB)
widest full NDJSON line : 4398 bytes (4.29 KiB)      implementer claim: ~4.5 KiB
32 MiB / line           : 7629 paths                 implementer claim: ~7,000
sample float rendering  : -0.8838327756636011
```

**Accurate.** The ~8 KiB/path stderr figure gives 4,096 paths at the same ceiling, also consistent.
This is a derived constant, not a picked one, and the derivation is recorded on the constant itself.

### F1 (LOW) — "the bound cannot bite legitimate output" is too strong

`essentia_python.rb:34-36` claims the ceiling is "far beyond any batch this gem is asked to run —
callers analyze one path or a handful — so the bound cannot bite legitimate output."

That is true of *current* usage but not of the *public API*. `Extractor#analyze_all(paths, descriptors:)`
(`extractor.rb:75`) is public, and it funnels **every path through one subprocess and one stdout
stream** — `run_analysis` passes `*pathnames.map(&:to_s)` in a single command
(`essentia_python.rb:~230`), and `parse_results` expects one NDJSON line per path from that one stream.
So stdout scales linearly with batch size, and at 4.29 KiB/path the ceiling lands at **~7,600 paths**.

I checked whether something else caps batch size first — it does not:

```
ARG_MAX                     : 1048576 bytes
paths before argv overflow  : ~13107  (at ~80 B/path)
paths before stream ceiling : ~7629
which binds first           : the 32 MiB stream ceiling
```

**Failure scenario:** a caller enriches a music library in one `analyze_all` call — 8,000 tracks is an
ordinary library — and gets `BackendError: … exceeded the 33554432 byte stdout limit`. Since
`BackendError` is a `FatalError`, the whole batch aborts.

**Why LOW rather than higher:** the failure is loud, correctly attributed, and cannot corrupt values —
which is the property that matters. This is a comment-accuracy issue with a mild operational
consequence. Suggested wording: scope the claim to the batch sizes this gem is *used* with, and note
that large-library callers should chunk `analyze_all`. Optionally, `analyze_all` could chunk internally.

---

## 7. Truncation is genuinely loud — **confirmed by execution**

Read first: `capture` calls `raise_stream_limit!(overflowed.first) unless overflowed.empty?` **before**
returning `captured` (`essentia_python.rb:60`), so the partial buffer cannot reach a caller. Verified
directly rather than by reading alone, with a sentinel in the payload:

```
RAISED BackendError, no Result returned
message: Essentia backend exceeded the 4096 byte stdout limit; the subprocess was terminated and its output discarded
message leaks payload bytes? no
```

No `Result` is constructed, and the message carries none of the payload — so neither the return value
nor the exception text can be mistaken for data. M3 (delete the raise) failing 4 examples is the gate
for this. Correct, and it is the right call: silently returning truncated NDJSON would corrupt
descriptor values, which is worse than the exhaustion prevented.

### About the intermittent error I chased — it was mine, not the code's

I repeatedly saw `0 examples, 0 failures, 1 error occurred outside of examples`. Cause: my first
mutation attempts used a double-quoted shell string containing `#\{described_class\}`, which passes the
backslashes through literally and writes **invalid Ruby** into the spec — a load error, hence zero
examples. A later harness compounded it by capturing rspec output in a command substitution.

Ruling it out took: 15/15 clean direct runs on the pristine tree, 5 random seeds all 208/0,
`diff` against `git show 3f1f511:…` confirming my scratch files were byte-identical to the commit, and
zero recurrence once the harness wrote to files instead of `$( )`. **Not a finding.** I am recording it
so nobody re-opens it, and because the near-miss is the same shape as a false finding I filed on a
previous ticket.

---

## 8. Order-dependent pollution — **gone, verified four ways**

Structurally the separation is right:
- `spec/support/recording_cli_analyze.rb` (the monkey-patcher) appears **only** as a `-r` flag string
  at `cli_spec.rb:88`, passed via `RUBYOPT` into the CLI **subprocess**. Never `require`d in-process.
- `spec/support/recording_cli_values.rb` is required in-process at `cli_spec.rb:73` and touches
  **nothing** — it defines a module with a frozen hash and a `fetch`. No `Sonance::Extractor` reference.

By execution:

```
cli_spec THEN extractor_spec, --order defined   -> 16 examples, 0 failures   (was 9 FAILURES before the fix)
extractor_spec alone                            ->  9 examples, 0 failures
full suite --order defined                      -> 208 examples, 0 failures
full suite, seeds 1 / 42 / 1337 / 99999 / 24304 -> 208/0 on every seed
```

And directly, after requiring the payload table in-process:

```
Extractor#analyze defined at: lib/sonance/extractor.rb   -> pristine
```

The reported reproduction (`cli_spec` then `extractor_spec` in defined order) is the exact case that
used to fail, and it now passes. **No suite-wide leakage remains.**

---

## 9. 194 → 208 — **coverage retained, but the delta is NOT purely additive**

I compared full example-description sets at base and HEAD rather than trusting the counts:

```
base examples: 194        head examples: 208        new in head: 15
base examples MISSING from head:
    LOST: sonance CLI passes comma-separated descriptor ids to analyze
```

So one pre-existing example was **removed** (194 − 1 + 15 = 208). The implementer's report says "five
examples replace the one that asserted on stub-shaped data," which is accurate but does not flag that a
named example disappeared. That deserved checking rather than assuming.

**Its behavioural coverage survives, and I proved it by mutation.** The removed example's unique
assertion was on the stub-shaped `{"path":…, "descriptors":[…]}` payload — exactly the blindness being
removed. Its *real* coverage (comma-separated ids reaching `analyze` correctly) is now exercised more
broadly, via `analyze_cli(Registry.default.ids.join(","))` — nine ids instead of two. To confirm it is
genuinely covered rather than incidentally present, I broke the comma splitting by dropping
OptionParser's `Array` coercion at `exe/sonance:34`:

```
mutation: dropped OptionParser Array coercion (no comma splitting)
7 examples, 4 failures
    cli:16, cli:32, cli:44, cli:55
```

**No coverage lost — coverage broadened.** Not a finding.

---

## 10. Could NOT verify

| Claim | Why not |
|---|---|
| The real 32 MiB boundary being hit end-to-end | Would require writing 32 MiB twice per example. The specs stub the ceiling to 4096 and assert the shipped constant separately (M5 gates that), which is the right trade — I verified the *logic* is ceiling-independent by reading, and M5/M6 gate both halves. |
| That the EPERM branch is covered on **Linux** CI | This host is macOS; Linux answers `ESRCH` for the same condition. Verified 10/10 on macOS only. |
| Behaviour against real Essentia | arm64 without the Essentia toolchain; all 14 `:essentia`-tagged examples remain excluded (208 of 222 with `ESSENTIA_SPECS=1`). Unchanged by this branch. |
| That the branch rebases cleanly onto `5647a12` | Out of scope per dispatch; the changed-file sets do not overlap the `#17`/`#19` files, so no conflict is expected. |

---

## 11. Evidence — commands

```
git -C <repo> log --format="%h %s" d514137..3f1f511
git -C <repo> diff --stat d514137 3f1f511
git -C <repo> diff --stat d514137 3f1f511 -- lib/sonance/registry.rb python/     -> empty
git -C <repo> diff d514137 3f1f511 -- lib/sonance/backends/essentia_python.rb
git -C <repo> show d514137:spec/support/recording_cli_analyze.rb                 (base stub, for I5M2)
git -C <repo> show d514137:lib/sonance/backends/essentia_python.rb | grep -A6 "def terminate"

# batteries: fresh `git archive 3f1f511 | tar -x` per mutation, harness aborts on missing anchor
/tmp/son56/battery.sh {control,M1,M2prime,M3,M4,M5,M6} <cr_spec> <ep_spec>
/tmp/son56/battery.sh {control,I5M1,I5M2} spec/cli_spec.rb

# EPERM branch coverage, 10 runs
(drop Errno::EPERM from kill_group) && for i in 1..10; rspec spec/backends/command_runner_spec.rb

# comma-parsing coverage
(drop OptionParser Array coercion at exe/sonance:34) && rspec spec/cli_spec.rb

# order dependence
rspec spec/cli_spec.rb spec/extractor_spec.rb --order defined
rspec --order defined ; rspec --seed {1,42,1337,99999,24304}
ruby -e 'Sonance::Extractor.instance_method(:analyze).source_location'

# additive-delta check
rspec --dry-run --format json | jq/ruby -> sorted full_description sets, base vs head, comm -23/-13

# constant derivation and loud truncation
ruby -e '<realistic full-precision NDJSON line measurement>'
ruby -e '<CommandRunner with 4096 ceiling, sentinel payload, assert no Result returned>'
getconf ARG_MAX
```

Scratch trees under `/tmp/son56/`; each battery run kept its own tree and output at
`/tmp/son56/b-<mutation>/.out`.

---

## 12. Summary

**APPROVE.** Both batteries reproduce exactly; both self-reported failures are real, fixed and gated;
the boundary is complete on both sides of both streams; the non-vacuity floor (M6) and the
real-`Analysis` dependency (#5 M2) both bite; truncation is loud and leaks nothing; the order-dependent
pollution is gone under defined order and five seeds; and the one removed example's coverage is proven
retained by mutation.

One LOW finding (F1, §6): scope the "cannot bite legitimate output" claim, since `analyze_all` can reach
the ceiling at ~7,600 paths. Worth a comment edit and possibly a follow-up on chunking; not a blocker.

Credit where due: this is the most self-critical implementer report I have reviewed on this project, and
both disclosures held up under independent checking. The `stub_const` + assert-the-shipped-constant
pattern, with M5 and M6 as its two floors, is the right way to test a bound cheaply without letting the
test pass against any constant.

## 13. Read-only confirmation

No commits, no edits to the repo, no pushes, no PR. All mutations ran in `/tmp/son56/` on fresh
`git archive` extractions, so the repository and its worktrees were never modified. Branch remains at
`3f1f511`.
