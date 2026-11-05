# SON-17 / #19 — Re-review, round 2

# VERDICT: **APPROVE**

**F1, F2, F3, F5 and F6 are CLOSED.** All three mandated mutations flip GREEN→RED, verified by my own
execution against an established control. No pre-existing example was weakened — the suite is
strictly *more* sensitive than in round 1. F4 remains open by design (it was never a merge blocker;
it is pre-#16 work).

One LOW residual and one correction to my own round-1 report are recorded below. Neither blocks.

Range reviewed: `965503d..11a1baf` (`c119c14` + `11a1baf`). Scope held to F1–F6 and fix-induced
regressions; I did not revisit the `verify!` restructure, layer ordering, digest pin, measured numpy
value, or #19 NOTICE.

---

## 1. Mutation battery — re-run independently, not taken on trust

Scratch copy at `/tmp/son1719-r2/gem` (rsync, `.git` excluded). Originals stashed and restored after
every mutation, with the control re-verified at the end.

**Unmutated control — established FIRST:**

```
$ bundle exec rspec --format progress
199 examples, 0 failures
```

Matches the implementer's claim.

| Mutation | Round 1 | **Round 2** | Failing example(s) |
|---|---|---|---|
| **(a)** `CANONICAL_NUMPY_VERSION` → `9.9.9` | 196/0 **GREEN** | **199, 7 failures** | see below |
| **(b)** detector hardcoded broken-open | 196/0 **GREEN** | **199, 1 failure** | `:215 .numpy_version returns 'unavailable' when the interpreter does not exist` |
| **(c)** `constraints.txt` → `numpy==9.9.9` | 196/0 **GREEN** | **199, 1 failure** | `:236 constraints.txt numpy pin matches CANONICAL_NUMPY_VERSION` |

Mutation (a) full failure list:

```
spec/canonical_essentia_environment_spec.rb:11  # accepts the uppercase Intel Xeon model reported by the failing GitHub runner
spec/canonical_essentia_environment_spec.rb:31  # accepts mixed-case Intel Xeon and AMD EPYC runner families
spec/canonical_essentia_environment_spec.rb:57  # rejects a non-x86 host while the same CPU family is accepted on x86_64
spec/canonical_essentia_environment_spec.rb:84  # rejects detected VirtualApple emulation while accepting a native runner CPU
spec/canonical_essentia_environment_spec.rb:187 # rejects a canonical CPU with the wrong numpy version and names both in the message
spec/canonical_essentia_environment_spec.rb:202 # accepts a canonical CPU with the correct numpy version
spec/canonical_essentia_environment_spec.rb:236 # constraints.txt numpy pin matches CANONICAL_NUMPY_VERSION
```

All three findings are genuinely closed. Note (a) is caught twice over — by the six numpy-sensitive
examples *and independently* by the F3 cross-check — which is the belt-and-braces I wanted.

---

## 2. THE QUESTION ASKED — did the `PINNED_NUMPY` swap weaken anything?

**No. Verified by re-running my round-1 CPU mutations on the new HEAD.**

| CPU mutation | Round 1 (base `d514137`) | **Round 2 (`11a1baf`)** |
|---|---|---|
| Neuter `EMULATED_CPU_PATTERN` | 2 failures | **2 failures** — same two examples (`:84`, `:140`; were `:71`/`:122` before line shift) |
| `verify!` → no-op | 7 failures | **8 failures** — one *more* |
| Neuter `NATIVE_CPU_PATTERN` | (not run in R1) | **4 failures** |

The `verify!` no-op mutation now produces **8** failures rather than 7, because the new
"accepts a canonical CPU with the correct numpy version" example (`:202`) also fails. **Strictly
strengthened, not weakened.** All 14 original CPU examples still assert what they asserted before.

### "Is there now any example that passes only because two literals coincidentally match?"

I isolated this directly: set the spec-side `PINNED_NUMPY` to `1.1.1` while leaving the guard's
`CANONICAL_NUMPY_VERSION` correct at `2.5.2`.

```
199 examples, 6 failures
:11  accepts the uppercase Intel Xeon model…          <- numpy-SENSITIVE
:31  accepts mixed-case Intel Xeon and AMD EPYC…      <- numpy-SENSITIVE
:57  rejects a non-x86 host while the same CPU family is accepted on x86_64
:84  rejects detected VirtualApple emulation while accepting a native runner CPU
:187 rejects a canonical CPU with the wrong numpy version…
:202 accepts a canonical CPU with the correct numpy version
```

So **six** examples require the two literals to agree — but this is the intended coupling, not
coincidence. Every one of the six contains a `not_to raise_error` branch (or asserts the numpy message
text). `PINNED_NUMPY` is now an *independent* literal asserting that the guard's constant is `2.5.2`;
if they diverge in either direction, six examples fail loudly. That is precisely the property F1 asked
for, and it is directional and correct:

- guard constant wrong, spec right → **7 failures** (mutation a)
- spec literal wrong, guard right → **6 failures** (isolation test above)

The remaining CPU examples are numpy-*independent*, because the CPU check fires before the numpy check
— unchanged from round 1, and correct. I also confirmed no numpy error can satisfy a CPU assertion: the
numpy message contains none of `native x86_64`, `unrecognised CPU model`, or `detected CPU emulation`.

### Irreducible residual — worth stating, not a finding

Moving **all three** literals together passes:

```
(d) guard + spec literal -> 9.9.9, constraints.txt left at 2.5.2   -> 199, 1 failure (:236 catches it)
(e) ALL THREE -> 9.9.9 (coordinated bump to a fictional version)   -> 199, 0 failures
```

No in-repo spec can verify that `2.5.2` is what pip actually resolves — only a canonical build can.
That is inherent, correctly handled by the measurement provenance recorded in `constraints.txt:5-10`,
and not something to fix in specs. Case (d) shows the cross-check does its job the moment the trio
falls out of step.

---

## 3. F2 — does the stub reproduce the injection-seam defect one level down?

**No, the fix is real — but there is a narrow LOW residual.**

The stub spec exercises the **genuine** code path. `python:` was already part of the method's
production signature (round 1's version had it with a default); no new seam was introduced. The stub is
a real executable, so `File.exist?`, the backtick subprocess, `.strip` and the `.empty?` branch all
execute for real. And the missing-interpreter example is what catches mutation (b) — a broken-open
detector, the worst failure mode, is now detected.

### F7 (NEW, LOW) — the stub pins the plumbing but not the command

The stub echoes `2.5.2` regardless of argv, so the spec does not verify *what is executed*:

```
##### corrupt the detector's COMMAND: import numpy -> import numpi #####
19:  result = `#{python} -c "import numpi; print(numpi.__version__)" 2>/dev/null`.strip
199 examples, 0 failures          <-- MISSED
```

**Why this is LOW and not a blocker, unlike the original F2.** A corrupted command makes the detector
return `"unavailable"`, which `!= "2.5.2"`, so `verify!` **raises loudly with the environment named**.
Verified:

```
detector -> "unavailable"
RAISED (fail-closed): Essentia goldens require numpy 2.5.2; detected numpy unavailable on Intel(R) Xeon(R) …
```

The original F2 could produce a **silent pass blessing any environment**. This residual can only
produce a *confusing red on the canonical builder* — annoying, never dangerous. Optional hardening: have
the stub assert its argv (`printf '%s\n' "$@" > argv.log`) and check the command string. Two lines,
entirely at the implementer's discretion.

---

## 4. F5 — can the guard and the extraction still disagree?

**Fixed, and fail-closed in every case I could construct.**

`numpy_version(python: ENV.fetch("SONANCE_PYTHON", "/usr/local/essentia-venv/bin/python3"))`.

| Case | Guard behaviour | Verdict |
|---|---|---|
| `SONANCE_PYTHON` **set**, interpreter **has** numpy 2.5.2 | detects `2.5.2` → passes; same interpreter extraction uses | **Agrees** |
| `SONANCE_PYTHON` **set**, interpreter has a **different** numpy | detects it → raises naming both versions | **Agrees, fail-closed** |
| `SONANCE_PYTHON` **set**, interpreter has **no** numpy | `"unavailable"` → raises (verified above) | **Agrees, fail-closed** |
| `SONANCE_PYTHON` **unset** | guard uses the absolute venv path; extraction uses bare `python3` | see below |

The unset case is the only residual asymmetry: the guard's default is the absolute
`/usr/local/essentia-venv/bin/python3`, while `essentia_golden_spec.rb:45` and
`generate_goldens.rb:14` default to bare `python3`. **In the canonical image these are the same
binary**, because `Dockerfile.essentia` puts the venv first on `PATH`. Outside the image the venv path
is absent, so the guard returns `"unavailable"` and raises — fail-closed again.

The absolute default is also *necessary*: `File.exist?("python3")` is false for a bare name, so
defaulting the guard to `"python3"` would make it report `"unavailable"` unconditionally. The
implementer's choice is correct. No finding.

---

## 5. F3 — parser robustness

Tested all three cases the dispatch named. **Robust; no finding.**

```
##### F3-a: constraints.txt MISSING #####
     Errno::ENOENT:
1 example, 1 failure                 <- loud, not a vacuous pass

##### F3-b: numpy pin line REMOVED #####
1 example, 1 failure                 <- regex yields nil, nil != "2.5.2"

##### F3-c: comment line "# example: numpy==9.9.9 would be wrong" added ABOVE the real pin #####
1 example, 0 failures                <- correctly ignored
```

`/^numpy==(\S+)/` is line-anchored, so a `#`-prefixed comment cannot match. I also confirmed exactly
one matching line exists today (`constraints.txt:35`), so the first-match behaviour is unambiguous. A
stray *uncommented* `numpy==` line would be picked up first — but that would also be a real pip
constraint conflict, so failing is the right response.

---

## 6. F6 — closed

```
Essentia goldens require numpy 2.5.2; detected numpy unavailable on Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz.
```

Doubled word gone. The sentinel is now `"unavailable"` (`canonical_essentia_environment.rb:17,20`).

---

## 7. Fix-induced regressions — none found

- **Protected paths untouched**, verified independently rather than trusting the report:
  ```
  $ git diff --stat 965503d 11a1baf -- lib/ python/ exe/ sonance.gemspec spec/fixtures/
  (empty)
  ```
  Across *both* rounds only five files changed: `Dockerfile.essentia`, `NOTICE`, `constraints.txt`,
  and the two canonical-environment files. No goldens, no registry, no `sonance_extract.py`.
- **RuboCop:** `49 files inspected, no offenses detected`.
- **The override short-circuit example is preserved** with `numpy_ver: "0.0.0"`
  (`spec/canonical_essentia_environment_spec.rb:116`). This matters: it proves
  `allow_non_canonical` returns *before* the numpy check, and it would have been easy to flatten to
  `PINNED_NUMPY` during the sweep. It was not. Good.
- **`c119c14` is comment-only** on `Dockerfile.essentia` (+3 lines) plus the `constraints.txt` record
  correction. No behaviour change.

---

## 8. A correction to my own round-1 report

Round 1 I credited the digest pin as *"a defensible way to pin `python3` without brittle apt version
strings."* **That was wrong, and `c119c14` correctly retracts it.** The `FROM` digest pins the base
image layers, but the subsequent `apt-get update && apt-get install python3` resolves against the live
Debian archive independently of that digest. So **python3 is recorded, not pinned** — as
`constraints.txt:14-30` now states explicitly, along with a sound reason for not apt-pinning (Debian
drops superseded versions at point releases, which would make the image unbuildable) and the correct
instrument if it is ever needed (`snapshot.debian.org`).

The implementer also caught that the original record used the `python3` *metapackage* version
(`3.13.5-1`), which is a pointer and inert as a drift detector, and replaced it with the real
interpreter revision `python3.13 3.13.5-2+deb13u3`. That is a genuine improvement on both my round-1
assessment and the original commit.

Consequence for F4: the unpinned-Python gap I listed is **still open**, now accurately documented
rather than wrongly believed closed. It remains pre-#16 work, not a merge blocker.

---

## 9. Status of all findings

| # | Round 1 | Round 2 |
|---|---|---|
| F1 constant-derived control | HIGH | **CLOSED** — mutation (a) 7 failures |
| F2 real detector unproven | HIGH | **CLOSED** — mutation (b) 1 failure. New LOW residual F7. |
| F3 constraints/constant drift | MEDIUM | **CLOSED** — mutation (c) 1 failure; parser robust |
| F4 numpy-only insufficient for bit-identity | MEDIUM | **OPEN by design** — pre-#16; python3 gap now accurately recorded |
| F5 guard vs extraction interpreter | MEDIUM | **CLOSED** — fail-closed in all constructed cases |
| F6 doubled word | LOW | **CLOSED** |
| F7 stub does not pin the command | — | **NEW, LOW** — fail-closed, optional hardening |

**F1, F2, F3, F5, F6 are closed.** F7 is new, low, and fail-closed. F4 is unchanged and was never a
blocker for this diff.

### Still outstanding for #16, carried forward unchanged from round 1

Not part of this diff, and the most important thing to keep visible: the committed goldens' values date
from `c74a15b` (2026-08-11) under an **unrecorded** numpy, and `golden/PROVENANCE.md` says they cannot
be re-derived. **A bit-identity gate must not be anchored to them.** Order must be: pin the environment
(done, here) → regenerate goldens under the pinned environment with numpy/TF/Python/CPU/image digest
recorded → then add #16's gate. Also still pending for #16: a full `pip freeze` from the built image
(which settles the essentia-tensorflow/TF-bundling question empirically) and narrowing
`NATIVE_CPU_PATTERN` to a single CPU family.

---

## 10. Could NOT verify on this machine — unchanged from round 1

| Claim | Why not |
|---|---|
| Goldens reproduce under numpy 2.5.2 | arm64, no TensorFlow; the CPU guard raises. Needs the amd64 Docker run specified in my round-1 report §0. |
| That `sha256:939bb27…` is the multi-arch OCI index the new comment describes | No network / cannot pull the manifest. The comment's *claim* is plausible and self-consistent, and the reasoning (child digest would break arm64 builds) is sound, but I am recording it as unverified rather than confirming it. |
| Whether `essentia-tensorflow` bundles libtensorflow | Cannot install the amd64 wheel here. |
| `python3.13 3.13.5-2+deb13u3` against packages.debian.org | No network. The implementer pasted the verification command and result; I did not independently confirm it. |
| That CI passes at `11a1baf` | Branch still unpushed — `git branch -r --contains 11a1baf` is empty, so no CI run exists. |

---

## 11. Repo state at finish — read-only honoured

```
$ git -C /Users/lukeolson/projects/gems/mood_probe rev-parse HEAD
d514137a09facf8c64519e189aed57c3abaf5635        # main, untouched
$ git -C … status --porcelain
?? .worktrees/                                   # pre-existing, untracked

$ git -C …/.worktrees/pin-python-stack-and-notice-uris rev-parse HEAD
11a1bafdb629b1fa8bfbc9349170d335e5c5fcca
$ git -C …/.worktrees/… status --porcelain
(empty — clean)
```

No commits, no edits, no pushes, nothing staged. All eleven mutations ran in `/tmp/son1719-r2/gem`;
originals restored after each and the control re-verified at **199 examples, 0 failures**.
