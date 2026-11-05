# SON-17 / #19 — Test & Gate Review

# VERDICT: **REQUEST-CHANGES**

Two HIGH findings, both the same shape: **the new numpy guard's comparison *logic* is tested, but its
pin *value* and its real *detector* are proven nowhere.** Three mutations that should break it leave
the suite at 196/0 green. The Dockerfile and NOTICE work is sound and I'd approve it as-is; the gate
needs three small specs before it can be trusted.

| # | Severity | Finding | Proof |
|---|---|---|---|
| F1 | **HIGH** | Non-vacuity pair derives its control from the constant under test, so a wrong pin value is undetectable | `CANONICAL_NUMPY_VERSION = "9.9.9"` → **196/0 green** |
| F2 | **HIGH** | The real `numpy_version` detector is called by no spec; broken-open detector passes | detector hardcoded to return canonical → **196/0 green** |
| F3 | MEDIUM | `constraints.txt` and the Ruby constant duplicate `2.5.2` with nothing cross-checking | `numpy==9.9.9` in constraints → **196/0 green** |
| F4 | MEDIUM | numpy-only is sufficient today but **not** for the bit-identity gate #17 exists to enable | reasoned + partially unverified, see §4 |
| F5 | MEDIUM | Guard checks numpy at a hardcoded venv path; extraction uses `SONANCE_PYTHON` | `essentia_golden_spec.rb:45` vs guard line 16 |
| F6 | LOW | Real-path message renders "detected numpy **numpy unavailable**" | pasted in §3 |

**Sequencing constraint that must be recorded before #16 proceeds** — see §0. It is not a defect in
this diff, but if it is not written down, #16 will produce a gate nobody can interpret.

---

## 0. THE HEADLINE — has anything verified the goldens still reproduce under numpy 2.5.2?

**No. And it cannot be determined from this machine.** But the dispatch's framing of the *risk* needs
correcting in a way that changes the priority.

### What I established by execution

The goldens' numeric values predate the pin, and nothing has run the comparison since:

```
$ git -C <repo> log --format="%h %ad %s" --date=iso -3 -- spec/fixtures/sonance/golden/
7aabc96 2026-08-13 16:20:43 -0700 Phase A: generalize mood_probe around a descriptor registry…

$ git -C <repo> log --format="%h %ad %s" --date=iso -1 c74a15b   # the origin commit PROVENANCE.md cites
c74a15b 2026-08-11 13:12:01 -0700 Implement plan-driven Essentia executor

$ git -C <repo> log --format="%h %ad %s" --date=iso -1 965503d   # the pin
965503d 2026-08-14 12:33:29 -0700 Pin numpy, base image digest, and Python version…

$ git -C <repo> branch -r --contains 965503d
(empty)                      # NOT pushed — no CI has ever run this branch
```

`golden/PROVENANCE.md` states the 08-11 values' environment is unrecorded, and that the 08-13 commit
only relabelled keys without regenerating measurements (ordered-value manifest SHA unchanged). So the
numbers date from **2026-08-11 under an unknown numpy**, and the pin was measured **2026-08-14**.

The golden comparison is not exercised by the implementer's 196-example run, and cannot be here:

```
$ bundle exec rspec --format progress | head -2
Run options: exclude {essentia: true}

$ ESSENTIA_SPECS=1 bundle exec rspec --tag essentia --dry-run   ->  14 examples
$ ESSENTIA_SPECS=1 bundle exec rspec --dry-run                  -> 210 examples
                                                    (196 ran, 14 essentia excluded)

$ ESSENTIA_SPECS=1 bundle exec rspec spec/integration/essentia_golden_spec.rb
6 failures — all from:
  raise <<~MESSAGE.strip
    #{rejection_reason(host_cpu, cpu_identifier)}
```

All six fail on the arm64 CPU guard — an environment failure, not a regression. **The implementer's
196/0 is correct and does not speak to the goldens at all.**

### The correction to the risk framing, and it matters

The dispatch's concern is that the pin "makes the gate red on the canonical builder for an environment
reason." **That specific failure mode is unlikely, for a verifiable reason:** the golden assertions are
tolerance-based, not bit-identity.

```
$ grep -n "golden_rel_tol\|be <=" spec/integration/essentia_golden_spec.rb
36:  let(:golden_rel_tol) { 1e-4 }
37:  let(:golden_abs_floor) { 1e-10 }
50:    it "keeps #{filename} within the calibrated cross-environment bound" do
159:        .to be <= comparison.fetch(:tolerance), message
```

The bound is **1e-4** and is *explicitly named* "calibrated **cross-environment** bound" — the gate is
designed to absorb environment differences. Per my #16 measurements, numpy-scale reduction-order
differences run **1e-7 to 1.5e-6**, i.e. absorbed by 100–1300×. **A numpy version change will not turn
the golden gate red.** What could turn red is the *new numpy guard itself*, and only if the builder
resolves something other than `2.5.2` — which `--constraint` now prevents.

So: this pin is currently **inert**. Every assertion it could protect is insensitive to numpy at this
magnitude. That is not an argument against it — #17 exists to make a *future* bit-identity gate
trustworthy — but it means the pin buys nothing today and its correctness is untested (F1–F3).

### The real consequence: a sequencing constraint for #16

Since the existing goldens were computed under an unrecorded numpy and `PROVENANCE.md` says they
cannot be re-derived, **a bit-identity gate must not be anchored to them.** The order must be:

1. Pin the environment (this diff, once F1–F3 are fixed).
2. **Regenerate the goldens under the pinned environment, recording numpy/TF/Python/CPU/image digest
   in `PROVENANCE.md`.**
3. *Then* add #16's bit-identity gate against those new bytes.

Skip step 2 and #16's gate is either red or accidentally green, with no way to tell which — which is
the exact trust failure #17 was opened to prevent. This is the single most important thing to carry
out of this review.

### The canonical run that would settle it

Not runnable here. On a native x86_64 Xeon/EPYC host with Docker:

```sh
git checkout 965503d
docker build --platform linux/amd64 -f Dockerfile.essentia -t sonance-essentia .
# confirm the constraint actually applied:
docker run --rm --platform linux/amd64 --entrypoint bash sonance-essentia \
  -c 'python3 -c "import numpy,sys;print(numpy.__version__, sys.version)"'   # expect 2.5.2
# then the existing CI essentia_golden job unchanged (fetch models, verify digests,
# capture outputs, run the gate). Green => goldens survive 2.5.2 within 1e-4.
```

Note even a green result only proves *tolerance* survival, not bit-identity. For step 2 above you want
the captured values recorded, not just a pass.

---

## 1. Is numpy-only sufficient? — **Sufficient today, insufficient for a bit-identity gate**

Arguing it rather than noting it, as asked.

### What numpy==2.5.2 does pin, and it is more than it looks

numpy wheels bundle their own BLAS, so pinning the wheel pins that too:

```
$ python3 -c "import numpy; print(numpy.__config__.CONFIG['Build Dependencies']['blas'])"
bundled BLAS: accelerate unknown        # (this arm64 wheel; linux wheels bundle OpenBLAS)
```

So BLAS version drift — a plausible worry — is *not* a separate hole. Good.

### What it does not pin — and this is the argument

**(a) numpy dispatches reduction kernels on CPU features at RUNTIME.** Verified — numpy reports a
compile-time baseline *and* a separately-detected runtime set:

```
$ python3 -c "import numpy as np; print(np.__config__.CONFIG['SIMD Extensions'])"
runtime SIMD baseline : ['NEON', 'NEON_FP16', 'NEON_VFPV4', 'ASIMD']
runtime SIMD dispatch : ['ASIMDHP', 'ASIMDDP']
```

The `found`/dispatch set is chosen from the CPU at import time. And the canonical guard deliberately
accepts **two different microarchitectures**:

```ruby
spec/support/canonical_essentia_environment.rb:5
NATIVE_CPU_PATTERN = /(?:Intel\(R\)\s+Xeon\(R\)|AMD\s+EPYC)/i
```

Intel Xeon Platinum and AMD EPYC do not expose identical AVX-512 feature sets, so one pinned numpy can
select different float32 reduction kernels on the two. **Pinning the numpy version does not pin the
kernel numpy runs.** For a 1e-4 tolerance gate this is irrelevant; for bit-identity it is fatal.

**I could NOT demonstrate this divergence and I am not going to assert it.** I tried:

```
$ python3 simd.py
n=39 mean=0.4836900532245636 | n=119 mean=0.4643615186214447 | n=313 mean=0.49165633320808411
$ NPY_DISABLE_CPU_FEATURES="ASIMDHP ASIMDDP" python3 simd.py
n=39 mean=0.4836900532245636 | n=119 mean=0.4643615186214447 | n=313 mean=0.49165633320808411
```

Identical — because the only disableable features on this arm64 host (half-precision, dot-product) are
not used by float32 `sum`. The x86 AVX-512-vs-AVX2 case is where it would show and I cannot test it
here. **Status: structurally supported, empirically unverified.** The honest framing is that this is a
reason to *narrow the CPU allowlist to one family* before relying on bit-identity, not a proven defect.

**(b) TensorFlow determines the values being reduced**, which matters more than the reduction order —
a TF change moves the inputs, not just the summation. `essentia-tensorflow==2.1b6.dev1389` is pinned
exactly (`Dockerfile.essentia:12-15`), and no separate `tensorflow` pip package is installed. **I
believe that wheel bundles its own libtensorflow (that being why it is a distinct distribution from
plain `essentia`), so TF is pinned transitively — but I could not verify it**, because this host has
plain `essentia 2.1-beta6-dev` with no TensorFlow and I cannot install the amd64 wheel. If it does
*not* bundle, TF is unpinned and that is a second hole. **One command on the builder settles it:**
`pip show essentia-tensorflow` / `pip freeze` inside the built image.

### Verdict on Q1

For the assertions that exist today: **numpy-only is more than sufficient** — nothing is even sensitive
to it. Before a bit-identity gate lands, three things are needed beyond the numpy pin: a **full `pip
freeze`** captured from the built image and committed (this also resolves the TF question empirically
rather than by argument), a **single CPU family** in `NATIVE_CPU_PATTERN`, and the regenerated goldens
from §0.

---

## 2. Is the guard proven only through its injection seam? — **YES, and it is worse than that**

This was the right thing to ask; it is the same defect class as the frozen-baseline specs.

### F2 (HIGH) — the real detector is proven nowhere

`numpy_version` (`spec/support/canonical_essentia_environment.rb:16-21`) is called by **no spec**. All
16 `verify!` calls inject `numpy_ver:`:

```
$ grep -rn "numpy_version" spec/ | grep -v "numpy_ver: "
spec/support/canonical_essentia_environment.rb:16:  def self.numpy_version(python: "…")
   (definition only — no spec reference)
```

Mutation — hardcode the detector **broken-open**, always reporting the canonical version:

```ruby
def self.numpy_version(python: "…")
  return CANONICAL_NUMPY_VERSION          # <- detector neutered
  result = `#{python} …`
end
```
```
196 examples, 0 failures          <-- MISSED
```

A permanently broken-open detector — the single worst failure mode for this guard, since it would
bless *any* environment — is invisible. Control: 196/0 on the unmutated scratch copy.

Only a *crashing* detector is caught, and incidentally:

```
=== detector raises ===
196 examples, 1 failure
  1) …prevents the golden generator from writing on arm64 before model loading
     expected "…canonical_essentia_environment.rb:17:in 'numpy_version': detector exploded…"
       to match /goldens require native x86_64.*host is arm64/i
     # ./spec/canonical_essentia_environment_spec.rb:180
```

That subprocess spec at `:180` reaches the real default path only because Ruby evaluates default
arguments eagerly — `numpy_ver:` is computed at line 27 *before* the CPU check raises at line 30. So on
arm64 the detector runs and its result is discarded every call. Harmless, but it is the only reason
M4 was caught at all, and it asserts a *CPU* message — it is not detector coverage.

**Fix (cheap — the seam already exists).** `numpy_version` takes `python:`. Two specs:

```ruby
it "reports numpy unavailable when the interpreter is absent" do
  expect(CanonicalEssentiaEnvironment.numpy_version(python: "/nonexistent"))
    .to eq("numpy unavailable")
end

it "parses the version printed by the real interpreter" do
  Dir.mktmpdir do |dir|
    stub = File.join(dir, "python3")
    File.write(stub, "#!/bin/sh\necho 2.5.2\n"); File.chmod(0o755, stub)
    expect(CanonicalEssentiaEnvironment.numpy_version(python: stub)).to eq("2.5.2")
  end
end
```

### F1 (HIGH) — the non-vacuity pair cannot detect a wrong pin value

`spec/canonical_essentia_environment_spec.rb:5`:

```ruby
CANONICAL_NUMPY = CanonicalEssentiaEnvironment::CANONICAL_NUMPY_VERSION
```

Both new examples derive their expectation from the constant under test — the control passes
`numpy_ver: CANONICAL_NUMPY`, and the perturbation asserts `include("numpy #{CANONICAL_NUMPY}")`.
So the pin's *value* is never asserted. Mutation:

```
=== CANONICAL_NUMPY_VERSION 2.5.2 -> 9.9.9 (constraints.txt untouched) ===
8:  CANONICAL_NUMPY_VERSION = "9.9.9".freeze
196 examples, 0 failures          <-- MISSED
```

The guard would then reject the *correct* builder environment and demand a numpy that does not exist,
and no spec would notice. **This repo already knows better** — `spec/baseline_v0_1_0_parity_spec.rb`
carries the comment *"The decimal literals are independent calibration controls… deriving them from
RELATIVE_TOLERANCE would let the control move with the bound."* The same reasoning applies verbatim
here and was not applied. Fix: assert the literal `"2.5.2"` in at least the perturbation example, plus F3.

---

## 3. Does the failure message name both CPU and numpy on the REAL path? — **YES, verified**

Not just the injected one. I forced the CPU checks to pass so the **real** detector reached the **real**
message path:

```
$ ruby -e 'require_relative "spec/support/canonical_essentia_environment"
           puts CanonicalEssentiaEnvironment.numpy_version.inspect
           CanonicalEssentiaEnvironment.verify!(host_cpu: "x86_64",
             cpu_identifier: "Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz",
             allow_non_canonical: false)'

real detector on this machine: "numpy unavailable"
RAISED via REAL detector path:
Essentia goldens require numpy 2.5.2; detected numpy numpy unavailable on Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz.
A numpy version mismatch indicates environment drift, not a code regression.
Update constraints.txt and CANONICAL_NUMPY_VERSION together after re-measuring on linux/amd64.
Set SONANCE_ALLOW_NON_CANONICAL=1 only for deliberate non-canonical investigation.
```

Both values come from parameters, so the real path interpolates real data. **Fail-closed confirmed:**
a missing interpreter yields `"numpy unavailable"`, which `!= "2.5.2"`, so it raises rather than
skipping. That is the correct design and it works.

**F6 (LOW):** the sentinel renders as `detected numpy numpy unavailable`. Cosmetic, but this is the
exact message a misconfigured builder will show, and doubled words read like a bug in the guard.
Suggest the sentinel be `"unavailable"`, or interpolate as `detected #{numpy_ver}`.

---

## 4. Do `constraints.txt` and the Ruby constant drift silently? — **YES (F3, MEDIUM)**

`2.5.2` is written twice with nothing tying them:

- `constraints.txt:18` — `numpy==2.5.2`
- `spec/support/canonical_essentia_environment.rb:8` — `CANONICAL_NUMPY_VERSION = "2.5.2".freeze`

```
=== constraints.txt numpy==2.5.2 -> numpy==9.9.9 ===
numpy==9.9.9
196 examples, 0 failures          <-- MISSED
```

The Dockerfile would install 9.9.9 (or fail to resolve) while the guard demanded 2.5.2, or vice versa.
Exactly the duplicate-descriptor-list shape from the earlier audit: one source of truth, two copies,
no gate. The comment at `constraints.txt:14-17` *instructs* the reader to update both together — which
is a comment, not a gate, and this is the same "comment rather than a gate" pattern #17 itself was
opened to fix.

**Fix — two lines, runs in the plain suite, no Docker:**

```ruby
it "keeps constraints.txt and CANONICAL_NUMPY_VERSION in agreement" do
  pinned = File.read(root.join("constraints.txt"))[/^numpy==(\S+)$/, 1]
  expect(pinned).to eq(CanonicalEssentiaEnvironment::CANONICAL_NUMPY_VERSION)
end
```

This also closes F1's value gap if the literal is asserted on one side.

---

## 5. F5 (MEDIUM) — the guard validates a different interpreter than the one that works

- Guard: `numpy_version(python: "/usr/local/essentia-venv/bin/python3")` — hardcoded (line 16).
- Extraction: `python_executable: ENV.fetch("SONANCE_PYTHON", "python3")`
  (`spec/integration/essentia_golden_spec.rb:45`, `spec/fixtures/sonance/generate_goldens.rb:14`).

In the default Docker case these agree, because `Dockerfile.essentia:17` puts the venv first on `PATH`,
so bare `python3` *is* the venv python3. But if `SONANCE_PYTHON` is set — and both call sites invite it
— **the guard blesses the venv's numpy while a different interpreter does the extraction.** The guard
should interrogate the interpreter that will actually run, i.e. take the same `SONANCE_PYTHON` default.

---

## What is sound — credited, since it should not be relitigated

Verified by execution and reading:

- **`verify!` restructure preserves precedence.** The override still short-circuits first; the CPU
  error still takes priority over numpy. All 14 pre-existing CPU examples pass unchanged, and the
  arm64 subprocess spec at `:180` still asserts the CPU message.
- **Fail-closed on a missing interpreter** — §3.
- **Dockerfile layer order is right**: `COPY constraints.txt .` precedes the `pip install`, so
  `--constraint` resolves. `WORKDIR` moved up accordingly. Verified in the diff.
- **`FROM` pinned by digest** (`ruby@sha256:939bb27…`) — this closes the mutable-tag hole I raised in
  #16, and pinning the base OS layer is a defensible way to pin `python3` without brittle apt version
  strings. The reasoning in the implementer report is correct.
- **numpy pin was MEASURED on the real amd64 builder, not inferred** — exactly what #16 asked for, and
  the method is recorded in `constraints.txt:7-13` with a date. Good provenance discipline.
- **#19 / NOTICE**: I re-derived the six `source_url` values from `lib/sonance/registry.rb` rather than
  trusting the report's list; all six are distinct and match. No findings.

---

## Verified by execution vs could NOT verify

**Verified:** SHAs, branch/worktree state, main untouched at `d514137`; the full diff; control
196/0; all five mutations (M1 wrong constant, M2 constraints drift, M3 broken-open detector, M4
raising detector, plus the restore); 14 essentia examples excluded locally and 6 failing on the arm64
guard with the CPU message; the real-detector message path; `numpy_version` having zero spec callers;
golden-fixture and pin commit dates; branch not pushed; golden tolerance values; numpy's runtime SIMD
dispatch reporting and bundled BLAS.

**Could NOT verify, and why — not guessed:**

| Claim | Why not |
|---|---|
| Goldens reproduce under numpy 2.5.2 | arm64, no TensorFlow, guard raises. Needs the §0 amd64 Docker run. |
| Whether numpy 2.5.2 existed on 2026-08-11 (when goldens were computed) | No network. Circumstantial only: local numpy `2.4.6` installed `2026-07-23`, builder resolves `2.5.2` on `2026-08-14`, so a minor bump occurred in that ~3-week window and the goldens sit inside it. **Suggestive, not conclusive** — different platforms, so not a clean comparison. |
| Whether `essentia-tensorflow` bundles libtensorflow (i.e. TF is transitively pinned) | Cannot install the amd64 wheel here. One `pip freeze` in the built image settles it. |
| Whether SIMD dispatch changes float32 reduction across Xeon vs EPYC | arm64 only; the disableable features here do not affect float32 `sum`. |
| That the `ruby@sha256:939bb27…` digest is the real `4.0.1-slim` amd64 manifest | Cannot pull the amd64 manifest from here. |
| That the essentia CI jobs pass at HEAD | Branch unpushed; no CI run exists. |

---

## Required changes (all small, all in the plain suite)

1. **F2** — two specs for `numpy_version` via its existing `python:` seam: missing interpreter →
   `"numpy unavailable"`; stub interpreter → parsed version. *(HIGH)*
2. **F1 + F3** — assert the literal `"2.5.2"` and cross-check it against `constraints.txt`. One spec
   closes both. *(HIGH / MEDIUM)*
3. **F5** — have the guard interrogate `ENV.fetch("SONANCE_PYTHON", …)`, the interpreter that actually
   runs. *(MEDIUM)*
4. **F6** — drop the doubled "numpy" in the unavailable message. *(LOW)*
5. **§0** — record the sequencing constraint on #16 (regenerate goldens under the pinned environment
   *before* anchoring a bit-identity gate). Not a code change; a note on #16 and in
   `golden/PROVENANCE.md`. **This is the highest-value item in this review.**
6. **F4** — before #16's gate lands, commit a full `pip freeze` from the built image and narrow
   `NATIVE_CPU_PATTERN` to one CPU family. Not required to merge this diff. *(MEDIUM)*

Items 1–4 are roughly 25 lines of spec and no production change. I'd re-review on the new HEAD.

## Repo state at finish — read-only honoured

```
$ git -C /Users/lukeolson/projects/gems/mood_probe rev-parse HEAD
d514137a09facf8c64519e189aed57c3abaf5635        # main, unchanged
$ git -C … status --porcelain
?? .worktrees/                                   # pre-existing, untracked
$ git -C … worktree list
…/mood_probe                                        d514137 [main]
…/mood_probe/.worktrees/pin-python-stack-and-notice-uris  965503d [fix/pin-python-stack-and-notice-uris]
```

No commits, no edits, no pushes, nothing staged. All mutations ran in `/tmp/son1719-scratch/gem`
(rsync copy, `.git` excluded); originals restored and re-verified after each.
