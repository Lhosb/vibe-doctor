# sonance #17 — build reproducibility review

**Reviewer:** Keystone (Principal Engineer) · **Date:** 2026-08-14
**Range:** `d514137a09facf8c64519e189aed57c3abaf5635..965503d2d1055e302141122d7b42db53be7d5df7`
**Branch:** `fix/pin-python-stack-and-notice-uris`
**Scope:** build-reproducibility claims only. Gate quality is Litmus's half and is not duplicated here.

**Status:** written incrementally; sections appended as each fact is established.

---

## VERDICT: APPROVE

*(one MUST-FIX before issue #17 is closed, not before merge — see the full verdict at the end)*

**The digest is the MULTI-ARCH INDEX, not the amd64 manifest. The pin is correct and arm64 laptops
can still build.** The implementer's "the FROM digest implicitly pins python3" claim is **false** and
I proved it empirically — but the code is sound and the conclusion it led to was right anyway.

---
## 1. THE DIGEST QUESTION — SETTLED

**`sha256:939bb2710ba0a49ffdba9470b4e562c9dfc5ee6718ba5a5214f1d421d0414d29` is the MULTI-ARCH
MANIFEST INDEX, not the amd64-specific manifest. The pin is correct. arm64 laptops can still build
`Dockerfile.essentia`. Your concern does not materialise.**

Determined against the Docker Hub registry API directly — no docker daemon required, so this is
verifiable by anyone on the team:

```
$ curl -sI -H "Accept: <all four manifest media types>" \
    https://registry-1.docker.io/v2/library/ruby/manifests/sha256:939bb271...
HTTP/2 200
content-type: application/vnd.oci.image.index.v1+json
docker-content-digest: sha256:939bb2710ba0a49ffdba9470b4e562c9dfc5ee6718ba5a5214f1d421d0414d29
```

`application/vnd.oci.image.index.v1+json` is the OCI **image index** media type. A platform-specific
manifest would have returned `application/vnd.oci.image.manifest.v1+json`. The body confirms it —
a `manifests` array with eight real platforms:

```
linux/amd64    -> sha256:48ef6188374caa1f32b970bcf82777bea762156a7da1751572166f7c938fab20
linux/arm64v8  -> sha256:c1c60b495f8ce42f8b6a8e20195cc76325355aed7d9827b8ad2602761da687aa
linux/armv5    -> sha256:c72e5bb02646d9c73c5bb920453021b323bb63aea649be2dbc917d9d553004a3
linux/armv7    -> sha256:448f09cd4caa018e91984ea662ed427a5b692964f916a6553051b1d522f0400d
linux/386      -> sha256:00e219d9854791f0ddc5b87504ff5e4aea45d346e84d7cf4546ff08a3cdbd0ab
linux/ppc64le  -> sha256:8d910c69dcf2ed3382238c34d68f126a7f4ab3974a7577a58d9bcdf8a1316db1
linux/riscv64  -> sha256:39ad4217f39d8b4c2de1ff83856a760b8165bee83ea395edd589dd7d6d649a2c
linux/s390x    -> sha256:1f2e079ba75eec203a909b49113edb9acdc5f34a93d9106cab9923b0a5f1b122
(+ 8 unknown/unknown attestation manifests)
```

**`linux/arm64v8` is present.** An arm64 machine resolving this index gets
`sha256:c1c60b49…` and builds normally.

**The digest that would have been wrong** — the one your worry describes — is the amd64 child,
`sha256:48ef6188374caa1f32b970bcf82777bea762156a7da1751572166f7c938fab20`. It is not what was
recorded.

### It is also the right tag

Resolving tags in `library/ruby` to their index digests:

| Tag | Index digest |
|---|---|
| **`4.0.1-slim`** | **`sha256:939bb271…`** ← identical to the pin |
| `4.0.1-slim-trixie` | `sha256:939bb271…` (same image; `slim` currently aliases `trixie`) |
| `4.0.1` | `sha256:63630ac6…` |
| `4.0.1-slim-bookworm` | `sha256:032217f0…` |

The pin resolves to exactly the tag it replaced. The amd64 child's config blob confirms
`RUBY_VERSION=4.0.1`, `architecture: amd64`, 5 layers (consistent with `-slim`).

### And pinning the index digest is the correct call

Not merely harmless — it is the right choice, for three reasons:

1. **It preserves multi-arch resolution.** Docker resolves the index against the build platform, so
   the same Dockerfile works on the amd64 builder and on arm64 laptops. Pinning the amd64 child would
   have hard-coded the architecture into a file that says nothing about architecture.
2. **It is exactly as immutable as the child.** Both are content-addressed. The index cannot be
   repointed; a rebuilt `ruby:4.0.1-slim` publishes a *new* index digest and the pin keeps resolving
   to the old one. Reproducibility is fully achieved.
3. **The architecture constraint belongs where it already is.** `CanonicalEssentiaEnvironment.verify!`
   enforces native x86_64 with a detector, and produces an honest, specific message. That is the
   right layer for it — a manifest-resolution error would be, as you say, obscure.

**One residual caveat, and it is minor.** Because the index resolves per-platform, an arm64 laptop
building this file gets an arm64 Essentia stack whose numpy build differs from the canonical amd64
one. That is not a regression — it was equally true with the `4.0.1-slim` tag — and it is caught
downstream by `verify!`. Worth a one-line Dockerfile comment noting the index is deliberate; not
worth blocking on.

---

## 2. "The FROM digest implicitly pins python3" — TESTED, AND IT IS FALSE

Implementer report lines 106–109:

> "Since the FROM digest now pins the entire base OS layer, python3 is implicitly pinned as a result."

**That is not true, and I tested it rather than reasoning about it.** Your suspicion was correct.

A base-image digest pins the layers *that were in the image when it was published*. It does not pin
what `apt-get update && apt-get install python3` fetches afterwards — that resolves against
`deb.debian.org`, which is mutable and independent of the image. `Dockerfile.essentia` still runs:

```dockerfile
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential python3 python3-venv ffmpeg && \
```

`ruby:4.0.1-slim` is Debian **trixie** (proved in §1: `4.0.1-slim` and `4.0.1-slim-trixie` are the
same index digest). Querying that archive directly:

```
$ curl -s https://deb.debian.org/debian/dists/trixie/Release
Suite: stable          Codename: trixie
Version: 13.6          Date: Sat, 11 Jul 2026 09:02:23 UTC
```

**The suite is at point release 13.6 — it has been revised six times since 13.0.** And the packages
themselves:

| Package | Version in trixie/main today |
|---|---|
| `python3` (metapackage, src `python3-defaults`) | `3.13.5-1` |
| `python3-venv` (metapackage) | `3.13.5-1` |
| `python3-minimal` (metapackage) | `3.13.5-1` |
| **`python3.13` — the actual interpreter** | **`3.13.5-2+deb13u3`** |

The `+deb13u3` suffix is the proof: the interpreter package has been revised **three times** within
Debian 13 while the `python3` metapackage version sat unchanged at `3.13.5-1`. `apt-get install
python3` pulls `python3.13` as a dependency and resolves it to whatever is current at build time —
`+deb13u3` today, `+deb13u4` after the next security update. The FROM digest has no bearing on that.

### Two distinct problems, both in the record rather than the code

**(a) The recorded version is the wrong field.** `constraints.txt` and the report record "python3
3.13.5" / "apt package `python3 3.13.5-1`". That is the *metapackage* — a pointer meaning "the default
python3 is 3.13". It will read `3.13.5-1` across many interpreter revisions, so as a drift detector it
is inert. The value worth recording is `python3.13 3.13.5-2+deb13u3`.

**(b) The implicit-pinning claim is false**, per the above. If #17 is closed on the strength of it,
the repository will carry an unpinned Python interpreter that everyone believes is pinned — which is
worse than a known gap.

### But the implementer's *conclusion* was right, even though the justification was wrong

Report lines 107–108 argue that pinning `python3.13=3.13.5-2+deb13u3` in apt "is more brittle than
pinning the base image by digest." **That instinct is correct and I endorse it.** Debian removes
superseded versions from `deb.debian.org` at point releases, so an apt version pin turns into an
unbuildable image the moment the archive rolls — a hard failure with no recourse. Do **not** add the
apt pin.

If genuine OS-layer reproducibility is wanted later, the correct instrument is
`snapshot.debian.org` (a timestamped, immutable archive) substituted into `sources.list`. That is a
real change with real cost and it is out of scope here.

### How much does this actually matter? Less than it first appears — but say so honestly

Practical exposure is **low**, for reasons that should be written down rather than assumed:

- `numpy` is now pinned explicitly, and numpy is the documented mechanism of the reduce/take
  non-commutativity (issues #9/#16/#17). The float-behaviour risk is addressed by the pin that *was*
  added.
- numpy ships as a compiled `cp313` wheel. A `3.13.5-2+deb13u2 → +deb13u3` bump keeps the same ABI
  tag, so the **same wheel** installs either way.
- `essentia-tensorflow==2.1b6.dev1389` is pinned.

So this is a **correct-the-record** finding, not a broken-build finding. It does not block the merge.
It must block closing #17 as "Python stack pinned."

---

## 3. `COPY constraints.txt` BEFORE pip — ordering is correct, and it is the point

**Ordering works, and it does not invalidate the pip layer more often than necessary. It is in fact
the specific reason the expensive layer stays cached.**

Resulting order:

```dockerfile
RUN apt-get update ... install ... && rm -rf /var/lib/apt/lists /var/cache/apt/archives
WORKDIR /sonance
COPY constraints.txt .
RUN python3 -m venv /usr/local/essentia-venv && \
    /usr/local/essentia-venv/bin/pip install --no-cache-dir \
        --constraint /sonance/constraints.txt "essentia-tensorflow==2.1b6.dev1389"
ENV PATH="/usr/local/essentia-venv/bin:${PATH}"
COPY . .
RUN bundle install
```

- **Correctness:** `WORKDIR /sonance` precedes `COPY constraints.txt .`, so the file lands at
  `/sonance/constraints.txt`, exactly the absolute path `--constraint` names. ✓
- **Cache key:** the pip layer's parent is `COPY constraints.txt .`, a single small file. It
  invalidates only when that file's content changes — i.e. when the numpy pin is deliberately
  updated. That is the minimum possible.
- **The load-bearing part:** `COPY constraints.txt .` sits **before** `COPY . .`. Had constraints.txt
  arrived via `COPY . .` (forcing pip after it), **every source edit would rebuild the entire
  essentia-tensorflow install** — hundreds of MB, minutes of build. The chosen ordering is what
  prevents that. This is not incidental; it is the correct reason to do it this way.
- **Minor, non-blocking:** `python3 -m venv` moved out of the apt layer into the pip layer, so it
  re-runs whenever constraints.txt changes. Cost is a second or two. Not worth restructuring.
- **Harmless redundancy:** `COPY . .` later re-copies `constraints.txt` with identical content.

No change requested here.

---

## 4. Does anything alter a COMPUTED VALUE?

**Denied — no computed value changes, and I verified it by execution rather than by reading the
diff summary.**

```
$ git diff --stat d514137 965503d -- lib python exe sonance.gemspec
(empty)
```

No runtime Ruby, no `sonance_extract.py`, no CLI, no gemspec. The five changed files are
`Dockerfile.essentia`, `NOTICE`, `constraints.txt`, and two spec files. No registry rows, no golden
fixtures regenerated.

**The one candidate vector, examined:** pinning `numpy==2.5.2` *would* change computed values if pip
had previously resolved to something else. Per the implementer's measurement, an unconstrained
install of `essentia-tensorflow==2.1b6.dev1389` on the canonical amd64 environment already yields
numpy `2.5.2`. So the pin is a **no-op today** and a **freeze going forward** — which is exactly the
intent. **I could not independently reproduce that measurement** (see §5), so I am relying on the
implementer's evidence for that single number.

**Control-flow check on `verify!`,** since the refactor could have changed gate semantics silently:

| | Before | After |
|---|---|---|
| `allow_non_canonical == true` | return | return |
| CPU ok | return | fall through to numpy check |
| CPU bad | raise `rejection_reason` | raise `rejection_reason` (identical message) |

CPU semantics are preserved exactly; the only addition is the new numpy condition after a passing CPU
check. That is the intended new gate, and its quality is Litmus's half — I note only that the
refactor did not alter the pre-existing behaviour.

**One nit, spec-only, non-blocking:** `numpy_version` interpolates `python` into backticks
(`` `#{python} -c "…"` ``). The default is a constant path and callers are specs, so this is not a
security finding — but a `File.exist?`-guarded `IO.popen` with an argument array would be tidier. Not
worth a round trip.

---

## 5. WHAT I COULD NOT VERIFY

Stated plainly, because two of these are load-bearing for someone else's confidence:

1. **I did not build the image.** No docker daemon here. Everything in §1 was established against the
   Docker Hub registry HTTP API, which is why it is reproducible by anyone with `curl` — but I have
   not observed an actual `docker build` succeeding on either architecture.
2. **I did not reproduce the numpy `2.5.2` measurement.** That required the amd64 builder and a full
   `essentia-tensorflow` install. §4's "no computed value change" conclusion rests on the
   implementer's number for that one value. If it is wrong, the pin would change computed values —
   and the 196-example suite passing at HEAD is meaningful but not conclusive, since the golden specs
   are gated off on this machine.
3. **I did not confirm that `ruby:4.0.1-slim` ships no preinstalled python3.** The Dockerfile
   explicitly `apt-get install python3`, which would be redundant if it were preinstalled — strong
   evidence, but inference, not observation. It does not affect §2's conclusion either way: the
   explicit install resolves against the mutable archive regardless.
4. **I did not verify the six NOTICE source URLs resolve.** Out of the build-reproducibility scope I
   was given; flagging only so nobody assumes it was covered.

---

## VERDICT: APPROVE

The change is a genuine improvement over `d514137` and nothing in the shipped artifacts is broken.
The digest pin — the thing you could not check and were right to worry about — is **correct**: it is
the multi-arch index, it matches `4.0.1-slim` exactly, and arm64 laptops keep working. The layer
ordering is right for the right reason. No computed value changes.

**One MUST-FIX before issue #17 is closed** (not before merge):

> The claim that the FROM digest implicitly pins `python3` is false, proven in §2. Correct
> `constraints.txt`'s header to record the real interpreter version (`python3.13 3.13.5-2+deb13u3`,
> not the `python3` metapackage's `3.13.5-1`) and to state explicitly that the interpreter is **not**
> pinned and why pinning it via apt is deliberately rejected. Do not add an apt version pin.

Merging with an unpinned interpreter is a defensible engineering trade — the implementer's reasoning
reached the right answer. Closing #17 as "Python stack pinned" while that is untrue is not, and that
is the only thing standing between this change and being complete.

**Optional, one line:** a comment in `Dockerfile.essentia` noting the digest is the multi-arch index
and is deliberately not platform-specific, so the next person does not "fix" it into the amd64 child.
