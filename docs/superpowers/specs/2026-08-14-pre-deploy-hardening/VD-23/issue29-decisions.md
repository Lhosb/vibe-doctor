## Owner decisions recorded, 2026-08-14

### NonCommercial — satisfied

Vibe Doctor is **non-commercial, with no plans to monetize**. The CC BY-NC-ND NonCommercial term
is therefore satisfied by current use, and the concern raised as "obligation 2" in this issue does
not require remediation.

This is recorded rather than closed silently, because it is a **use-dependent** condition, not a
one-time fix. If the project later becomes commercial, the NC term reactivates and no packaging
change cures it — the options at that point would be commercial licensing of the models, swapping
to permissively-licensed models, or keeping the audio-grounding feature non-commercial. Anyone
revisiting this should treat a change in commercial status as re-opening the question.

### Application licence — MIT

The repository root will carry an **MIT LICENSE**, copyright Luke Olson, 2026.

MIT is defensible here for the same reason the sonance gem relies on: Essentia is invoked as a
**separate subprocess**, not linked, so AGPL-3.0 reciprocity is not triggered on the application's
own code. AGPL-3.0 was considered and not chosen.

**Scope limitation, which the NOTICE must state plainly:** MIT covers this repository's own code
**only**. It does not relicense the six Essentia model binaries, which remain CC BY-NC-ND 4.0, and
it does not relicense Essentia, which is AGPL-3.0. Because MIT is permissive, a downstream reader
could otherwise reasonably assume the models arrived under the same terms. Anyone redistributing
or using this repository takes on the model licences independently.

### Remaining work on this issue

Obligation 1, attribution, is in progress on branch `fix/model-attribution-notice`:
root NOTICE mirroring the gem's, naming the six redistributed model files by path, plus a root
LICENSE and a README pointer.

Removal of the six binaries from the tracked tree is **deliberately excluded** from that branch.
It is coupled to #23, whose plan is blocked pending confirmation that the remote builder has
egress to essentia.upf.edu. Removing them before #23 lands would break the production image,
because those tracked files *are* the models in the image today.
