## Problem

This repository is **public** (`gh repo view` confirms `"visibility":"PUBLIC"`) and redistributes
six Essentia model binaries with **no LICENSE and no NOTICE file at the repository root**.

The files are tracked in git:

```
$ git ls-tree -r -l origin/main | grep '\.pb$'
100644 blob 0bfd38d…    82458  tmp/essentia_models/danceability-msd-musicnn-1.pb
100644 blob 6de146e…    82460  tmp/essentia_models/emomusic-msd-musicnn-2.pb
100644 blob e3d6d8c…    82458  tmp/essentia_models/mood_acoustic-msd-musicnn-1.pb
100644 blob de9af07…    82458  tmp/essentia_models/mood_happy-msd-musicnn-1.pb
100644 blob 92d7dfd…    82458  tmp/essentia_models/mood_relaxed-msd-musicnn-1.pb
100644 blob f3466c8…  3197999  tmp/essentia_models/msd-musicnn-1.pb
```

They are deliberately re-included past the `tmp/` exclusion by `.gitignore:33-34` and
`.dockerignore:34-35`.

## Why this matters

The sonance gem ships a `NOTICE` precisely because these artifacts carry attribution
obligations. Its own text records the position:

- `NOTICE:9` — the compliance floor is **Creative Commons
  Attribution-NonCommercial-NoDerivatives**
- `NOTICE:11` — *"use is non-commercial under either reading"*
- `NOTICE:15` — *"Operators are responsible for reviewing and complying with the licenses"*

Vibe Doctor is the operator, and it currently carries none of that. A public repository
redistributing NC-ND licensed binaries with no attribution and no licence text is a live
compliance exposure, independent of any deployment concern.

## Two distinct obligations, do not conflate them

1. **Attribution / redistribution.** Addressed by removing the binaries from the public repo and
   adding a root `NOTICE` mirroring the gem's. This is a mechanical fix and is covered by the
   plan on #23.
2. **NonCommercial.** *Not* addressed by any packaging change. The NC term constrains **use**,
   not merely redistribution. If Vibe Doctor is or becomes a commercial product, fetching the
   models at build time instead of committing them does **not** cure it.

Obligation 2 is a decision for the repository owner and is **escalated, not assigned**. No
implementer should resolve it.

## Required work — obligation 1 only

- Add a root `NOTICE` recording the model licences and attribution, mirroring the gem's.
- Add a root `LICENSE` for the application itself, so the absence of one stops being ambiguous.
- Remove the six binaries from the tracked tree as part of #23's build-time-fetch plan.
- Do **not** rewrite git history for this. 3.44 MiB does not justify it, and the history rewrite
  would itself be a destructive operation on a public repo.

## Relationship to #23

#23 is the mechanism (where the bytes come from). This issue is the obligation (what must
accompany them). #23's accepted plan happens to resolve obligation 1 as a side effect, but that
is not a reason to track them together — if #23 is deferred or its plan changes, this obligation
does not go away.

## Provenance

Found by the Principal Engineer during the #23 design, 2026-08-14, while establishing where the
model bytes actually come from. Repo visibility, the absence of root LICENSE/NOTICE, the tracked
blobs, and the `NOTICE` line references were each re-verified independently by the Team Manager.
