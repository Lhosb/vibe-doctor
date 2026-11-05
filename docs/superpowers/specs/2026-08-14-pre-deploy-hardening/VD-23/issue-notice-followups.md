## Two NOTICE observations, both non-blocking, neither introduced by #23

Raised during the spec review of #23 at `cdc6dcb`, 2026-08-14. Both are inherited from the NOTICE
that landed via #29 (PR #31), so they did not gate that merge and do not gate #23. Filing so they
are not rediscovered by the next audit.

### O1 — the essentia-tensorflow disclosure names only AGPL-3.0

`NOTICE:12-16` discloses that `essentia-tensorflow==2.1b6.dev1389` (AGPL-3.0) is installed into
the deployed image at `/usr/local/essentia-venv`. That is accurate, and AGPL-3.0 is the correct
compliance floor for Essentia itself.

But the `essentia-tensorflow` wheel exists **precisely to carry TensorFlow**, which is Apache-2.0
and has its own attribution expectation — and no separate `tensorflow` package is installed
anywhere in the image. So the image plausibly ships an Apache-2.0 component that the NOTICE does
not mention.

**Status: BELIEVED, NOT VERIFIED.** The reviewer could not inspect the wheel's contents — this
machine is arm64 and the image was not built. Confirming it requires listing the wheel's bundled
libraries from a real `linux/amd64` build.

This is a licence-completeness question, not a false statement. Nothing currently in the NOTICE is
untrue.

### O2 — the obligation-transfer sentence is narrower than the rest of the file

`NOTICE:5-7` says obligations pass to "anyone redistributing or using **this repository**."

That was exactly right when the model bytes lived in the tracked tree. It is now narrower than the
file around it: since the NOTICE discloses that the deployed **image** carries both the models and
essentia-tensorflow, the party most affected is someone who pulls the image and never clones the
repository at all.

Not false — just scoped to the wrong artifact relative to everything else in the file.

### Suggested handling

Both are small wording changes to the same file and should land together, in one pass, rather than
as two edits. O1 should be **verified first** — do not add an Apache-2.0 attribution for TensorFlow
on the strength of an inference. Build the image, list what the wheel actually bundles, then write
what is true.

### Provenance

Spec review of #23 round 3, 2026-08-14, which walked all 18 claims in the NOTICE and confirmed the
other 17 are true. Recorded as observations rather than findings because neither is a false
statement and neither was introduced by the change under review.
