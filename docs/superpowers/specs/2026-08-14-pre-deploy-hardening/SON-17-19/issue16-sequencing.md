## Sequencing constraint — the bit-identity gate must NOT be anchored to the existing goldens

Test review of #17, 2026-08-14. This is not a defect in #17; it is a constraint on **this** issue
that has to be recorded before implementation starts.

### The problem

The existing golden values date from `c74a15b` (2026-08-11) and were computed under an
**unrecorded** numpy. `golden/PROVENANCE.md` states they cannot be re-derived. The numpy pin in
#17 was measured on 2026-08-14.

Nothing has ever run the golden comparison under numpy 2.5.2 — locally the 6 golden examples all
fail the arm64 CPU guard and 14 essentia examples are excluded, and the branch is unpushed so no
CI has run.

If #16's bit-identity gate is anchored to those existing goldens, it will be either red or
**accidentally green with no way to tell which** — precisely the trust failure #17 exists to
prevent.

### Required order

1. **Pin the environment** — #17.
2. **Regenerate the goldens under the pinned environment**, recording numpy, TensorFlow, Python,
   CPU and base-image digest alongside them in `PROVENANCE.md`.
3. **Then** add #16's bit-identity gate, anchored to the regenerated values.

Skipping step 2 is the failure mode. This should also be recorded in `golden/PROVENANCE.md`
itself, not only here, since that file is where the next person will look.

### Correction to an earlier framing

I raised the concern that pinning numpy might turn the **golden gate** red. That specific worry is
unlikely, for a verifiable reason: the golden assertion is **tolerance-based** at `1e-4`
(`essentia_golden_spec.rb:36`) and is explicitly named a *calibrated cross-environment bound*
(`:50`). Numpy-scale reordering differences are 1e-7 to 1.5e-6 — absorbed by 100× to 1300×.

So a numpy change will not redden the golden gate. What *could* redden is the new numpy guard
itself, and only if the builder resolves something other than 2.5.2, which `--constraint` now
prevents.

**Net: the pin is currently inert** — nothing that exists today is sensitive to numpy. That is not
an argument against it. It is the reason the pin must land *before* the bit-identity gate that
will be sensitive to it.

### A related gap that must close before this issue lands

`NATIVE_CPU_PATTERN` accepts **both** Intel Xeon and AMD EPYC — two microarchitectures with
different AVX-512 feature sets. numpy dispatches its reduction kernels on CPU features detected at
**runtime** (verified: numpy reports a compile-time baseline plus a separately detected runtime
set). So a single pinned numpy can select different float32 kernels on the two accepted families.

This is **structurally supported but empirically unverified** — the reviewer could not demonstrate
the divergence on arm64 and explicitly declined to assert it. It is recorded as a risk, not a
finding.

Before a bit-identity gate lands, two things should close it:

- commit a full `pip freeze` captured from the built image, which also settles empirically whether
  `essentia-tensorflow` bundles libtensorflow;
- narrow the CPU allowlist to **one** family.

In numpy's favour and worth recording so it is not re-investigated: numpy wheels bundle their own
BLAS, so BLAS version drift is **not** a separate hole. That was checked.
