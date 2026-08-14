# SON-17-19 Implementer Report

## Status: DONE

---

## Identifiers

- BASE_SHA: `d514137a09facf8c64519e189aed57c3abaf5635`
- HEAD_SHA: `965503d2d1055e302141122d7b42db53be7d5df7`
- Branch: `fix/pin-python-stack-and-notice-uris`
- Commit 1 (issue #19): `084399bd3fb3917c528669137cf571b0a9899089`
- Commit 2 (issue #17): `965503d2d1055e302141122d7b42db53be7d5df7`

---

## Commit 1 — issue #19: NOTICE licence URIs and source URLs

**Files changed:** `NOTICE` (1 file, +26 lines)

source_url derivation command:
```
grep -A 3 'source_url:' lib/sonance/registry.rb
```

The six models use Ruby line-continuation concatenation across two lines each (e.g.
`"https://essentia.upf.edu/models/classification-heads/danceability/" \ "danceability-msd-musicnn-1.pb"`).
Concatenated URLs as they appear in the file:

```
msd-musicnn-1.pb
  https://essentia.upf.edu/models/feature-extractors/musicnn/msd-musicnn-1.pb

danceability-msd-musicnn-1.pb
  https://essentia.upf.edu/models/classification-heads/danceability/danceability-msd-musicnn-1.pb

mood_acoustic-msd-musicnn-1.pb
  https://essentia.upf.edu/models/classification-heads/mood_acoustic/mood_acoustic-msd-musicnn-1.pb

mood_relaxed-msd-musicnn-1.pb
  https://essentia.upf.edu/models/classification-heads/mood_relaxed/mood_relaxed-msd-musicnn-1.pb

mood_happy-msd-musicnn-1.pb
  https://essentia.upf.edu/models/classification-heads/mood_happy/mood_happy-msd-musicnn-1.pb

emomusic-msd-musicnn-2.pb
  https://essentia.upf.edu/models/classification-heads/emomusic/emomusic-msd-musicnn-2.pb
```

All six differ; each is cited individually with the common base URL noted.
Existing ShareAlike-versus-NoDerivatives reasoning preserved verbatim.

---

## Commit 2 — issue #17: Pin Python stack

**Files changed:** 4 files, +96/-11 lines

| File | Change |
|------|--------|
| `constraints.txt` | Created — `numpy==2.5.2` with derivation instructions |
| `Dockerfile.essentia` | FROM pinned to digest; COPY constraints.txt before pip; `--constraint` flag added |
| `spec/support/canonical_essentia_environment.rb` | `CANONICAL_NUMPY_VERSION = "2.5.2"`; `numpy_version` method; `verify!` extended |
| `spec/canonical_essentia_environment_spec.rb` | All existing calls pass `numpy_ver: CANONICAL_NUMPY`; two new non-vacuity examples |

### How canonical numpy version was determined

**Method: MEASURED, not inferred.**

Ran on the Hetzner amd64 remote builder (ssh deploy@5.78.177.23) in a fresh container
replicating the exact Dockerfile.essentia environment:

```bash
docker run --rm --platform linux/amd64 ruby:4.0.1-slim \
  sh -c 'apt-get update -qq && apt-get install -y python3 python3-venv -q 2>/dev/null && \
  python3 -m venv /tmp/venv && \
  /tmp/venv/bin/pip install --no-cache-dir "essentia-tensorflow==2.1b6.dev1389" -q 2>/dev/null && \
  /tmp/venv/bin/python3 -c "import numpy; print(numpy.__version__)"'
```

Output: `2.5.2`
Python version (from same base): `3.13.5` (apt package `python3 3.13.5-1`)
Base image digest measured: `ruby@sha256:939bb2710ba0a49ffdba9470b4e562c9dfc5ee6718ba5a5214f1d421d0414d29`

This machine is arm64 (Apple). The measurement was done on the actual linux/amd64 build host,
not inferred from local state.

### Dockerfile.essentia changes

Before:
```
FROM ruby:4.0.1-slim
RUN apt-get ... && pip install --no-cache-dir "essentia-tensorflow==2.1b6.dev1389"
COPY . .
```

After:
```
FROM ruby@sha256:939bb2...  # pinned by digest
RUN apt-get ... (no pip yet)
COPY constraints.txt .      # must precede pip so --constraint is available
RUN pip install --no-cache-dir --constraint /sonance/constraints.txt "essentia-tensorflow==2.1b6.dev1389"
COPY . .
```

Note: python3 version (3.13.5) is recorded in constraints.txt comments. Pinning it at the
apt layer would require pinning the full Debian package name (e.g. `python3.13=3.13.5-1`)
which is more brittle than pinning the base image by digest. Since the FROM digest now
pins the entire base OS layer, python3 is implicitly pinned as a result.

### Non-vacuity proof (both directions)

**CONTROL — correct numpy version passes:**
```ruby
CanonicalEssentiaEnvironment.verify!(
  host_cpu: "x86_64",
  cpu_identifier: "Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz",
  numpy_ver: "2.5.2",
  allow_non_canonical: false
)
# => CORRECTLY PASSED
```

**PERTURBATION — wrong numpy version fails, message names both CPU and numpy:**
```ruby
CanonicalEssentiaEnvironment.verify!(
  host_cpu: "x86_64",
  cpu_identifier: "Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz",
  numpy_ver: "2.4.0",
  allow_non_canonical: false
)
# => CORRECTLY FAILED:
# Essentia goldens require numpy 2.5.2; detected numpy 2.4.0 on Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz.
# A numpy version mismatch indicates environment drift, not a code regression.
# Update constraints.txt and CANONICAL_NUMPY_VERSION together after re-measuring on linux/amd64.
# Set SONANCE_ALLOW_NON_CANONICAL=1 only for deliberate non-canonical investigation.
```

Failure message names: required numpy (2.5.2), detected numpy (2.4.0), CPU model. ✓

---

## Verification

### Full gem suite (HEAD):
```
196 examples, 0 failures
```

### RuboCop:
```
49 files inspected, no offenses detected
```
(--only-recognized-file-types; NOTICE and constraints.txt are plain text)

### Brakeman:
Not applicable — this is a plain Ruby gem (no Rails). Brakeman is not in the Gemfile and
does not run on gem codebases. The issue dispatch inherited the gate list from the Rails
app task; it does not apply here.

---

## RISK TRIGGERS TOUCHED

NONE — no schema migration, no auth, no money/binding documents, no data-exposure surface,
no destructive operations, no security config changes.

New files: `constraints.txt` (plain text pip constraints). No golden fixtures regenerated.
No `sonance_extract.py` touched. No registry rows changed. No computed values changed.

---

## Must-fix follow-up on issue #17 (record correction)

**HEAD_SHA (after follow-up):** `c119c14d62e18d33d42b24614cd1d85c980803bc`
Commit: `c119c14` — "Correct python3 version record and Dockerfile digest comment"

### python3.13 version verification

Verified directly against packages.debian.org before writing:
```
curl -s "https://packages.debian.org/trixie/python3.13" | grep -i "version\|3\.13\."
```
Result: `python3.13 (3.13.5-2+deb13u3)` — matches what the Principal relayed. Used this value.

The metapackage `python3 3.13.5-1` is a pointer; the +deb13uN suffix on `python3.13 3.13.5-2+deb13u3`
tracks actual interpreter revisions. The two are different things. The original constraints.txt
recorded the metapackage version, which is inert as a drift detector.

### Changes made

**constraints.txt:**
- Replaced `python3 3.13.5 from apt` (metapackage, inert) with `python3.13  3.13.5-2+deb13u3`
  (real interpreter, verified from Debian trixie archive)
- Added explicit statement: interpreter is recorded but NOT pinned
- Documented why apt pinning is rejected: Debian removes superseded versions at point releases;
  the pin becomes unbuildable when the archive rolls
- Named `snapshot.debian.org` as the instrument for full OS-layer reproducibility (out of scope)
- Removed the implicit-pinning claim (FROM digest does not pin what apt fetches afterward)

**Dockerfile.essentia:**
- Added comment that the FROM digest is the multi-arch OCI index, not the amd64 child manifest,
  and that replacing it with the child digest breaks arm64 builds

### Protected paths — empty diff confirmed

```
git diff --stat HEAD -- lib/ python/ exe/ sonance.gemspec spec/fixtures/sonance/golden/
```
(empty — no lib, python, exe, gemspec, registry, or golden files changed)

### Verification

- **bundle exec rspec:** 196 examples, 0 failures
- **rubocop --only-recognized-file-types:** 49 files inspected, no offenses detected

RISK TRIGGERS TOUCHED: NONE

---

## Test review must-fix: spec gaps F1/F2/F3/F5/F6

**HEAD_SHA:** `11a1bafdb629b1fa8bfbc9349170d335e5c5fcca`
Commit: `11a1baf` — "Close spec gaps F1/F2/F3/F5/F6 on canonical environment guard"

### Changes

**spec/canonical_essentia_environment_spec.rb** (+54/-20):
- **F1**: `CANONICAL_NUMPY = CanonicalEssentiaEnvironment::CANONICAL_NUMPY_VERSION` replaced with
  `PINNED_NUMPY = "2.5.2"` — literal, not derived from the constant under test.
  Reasoning from `baseline_v0_1_0_parity_spec.rb`: "decimal literals are independent calibration
  controls ... a constant-derived control moves with the bound."
- **F2**: Added `describe ".numpy_version"` block with two examples via the `python:` seam:
  - missing interpreter path → returns `"unavailable"`
  - stub shell script printing `2.5.2` → returns `"2.5.2"`
- **F3**: Added `"constraints.txt numpy pin matches CANONICAL_NUMPY_VERSION"` spec that parses
  `constraints.txt` with a regex and asserts its value equals the Ruby constant. Closes the
  silent-drift gap; failure message names both values.

**spec/support/canonical_essentia_environment.rb** (+3/-3):
- **F5**: `numpy_version` default changed from hardcoded venv path to
  `ENV.fetch("SONANCE_PYTHON", "/usr/local/essentia-venv/bin/python3")` — matches the extraction
  path used in `essentia_golden_spec.rb:45` and `generate_goldens.rb:14`.
- **F6**: `"numpy unavailable"` (doubled word) corrected to `"unavailable"`.

### Mutation battery — all three were GREEN before, all RED after

| Mutation | Example that fails | Direction |
|---|---|---|
| A. `CANONICAL_NUMPY_VERSION = "9.9.9"` | `constraints.txt numpy pin matches CANONICAL_NUMPY_VERSION` — "constraints.txt pins numpy==2.5.2 but CANONICAL_NUMPY_VERSION is 9.9.9" | **RED** ✓ |
| B. `numpy_version` hardcoded to return `CANONICAL_NUMPY_VERSION` | `.numpy_version returns 'unavailable' when the interpreter does not exist` — expected "unavailable", got "2.5.2" | **RED** ✓ |
| C. `constraints.txt numpy==9.9.9` | `constraints.txt numpy pin matches CANONICAL_NUMPY_VERSION` — "constraints.txt pins numpy==9.9.9 but CANONICAL_NUMPY_VERSION is 2.5.2" | **RED** ✓ |

### Unmutated GREEN control

```
199 examples, 0 failures
```

### All three mutations individually verified and restored before commit.

### Verification

- **bundle exec rspec:** 199 examples, 0 failures
- **rubocop --only-recognized-file-types:** 49 files inspected, no offenses detected (1 Layout offense autocorrected)
- **git diff --stat HEAD -- lib/ python/ exe/ sonance.gemspec:** empty

RISK TRIGGERS TOUCHED: NONE
