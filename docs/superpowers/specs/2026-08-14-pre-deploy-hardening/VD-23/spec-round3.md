# SPEC RE-REVIEW ROUND 3 — vibe-doctor issue #23 — NOTICE and README only

**VERDICT: APPROVE** on NOTICE and README. Every claim in the merged NOTICE is true at this HEAD, all
four states are kept distinct, README is consistent with it, and **neither half of the merge was
lost**. Two non-blocking observations, both inherited from `origin/main` rather than introduced by #23.

- REPO: `/Users/lukeolson/projects/vibe-doctor`
- HEAD: `cdc6dcbc8a02be14de1ac19ba4b88f3801ec86ef` (pushed; local == `origin/…` — confirmed)
- Parent / new base: `ff67619232dd43db008f9269555590cdf6d37409` == `origin/main`
- Previously approved: `6df28b9`
- Scope: **NOTICE and README only.** Dockerfile, spec paths, `.pb` deletions not re-reviewed, per dispatch.

---

## PREMISE CHECKS (all three confirmed)

**HEAD is stable this time.** Both the local branch and `origin/fix/fetch-models-at-build-time` read
`cdc6dcb`. After round 2's mid-review amend I re-checked; no movement.

**"Every file #23 itself touches is identical between `6df28b9` and `cdc6dcb`" — TRUE.** Restricting
the diff to exactly #23's files leaves only NOTICE:

```
$ git diff --stat 6df28b9 cdc6dcb -- .dockerignore .gitignore Dockerfile README.md NOTICE \
    spec/fixtures/sonance/generate_goldens.rb spec/integration/essentia_extract_golden_spec.rb tmp/essentia_models
 NOTICE | 6 ++++--
 1 file changed, 4 insertions(+), 2 deletions(-)
```

The other 27 paths that differ (`docs/…`, `essentia_mapper_spec.rb`) are **inherited from the new
base**, not #23's work — `git diff --name-only origin/main cdc6dcb -- docs/ spec/models/` is empty.
So the narrow scoping is justified.

**Litmus's scope point is correct and I accept ownership.** `#23`'s own commit substantively modifies
both files against the new base:

```
$ git diff --numstat origin/main cdc6dcb -- NOTICE README.md LICENSE
13	10	NOTICE
6	3	README.md
        <- LICENSE absent: genuinely inherited
```

Only `LICENSE` was inherited. NOTICE and README are #23's to answer for, and they are mine to review.

---

## THE MERGE: WAS EITHER HALF LOST?

**No. Both halves are present and they occupy different paragraphs.**

*From `origin/main` (the N1 fix I raised in round 2, which you applied on the attribution branch)* —
NOTICE `:12-16`. The round-2 wording "not linked into **or bundled with** the application" is gone,
replaced with an affirmative disclosure naming the version and path. **My N1 is fully discharged**,
and discharged the better way: not by deleting the false half but by stating the true fact.

*From #23* — NOTICE `:18-24` (model paragraph rewritten) and `:29-45` (list re-labelled). The
`origin/main` version still carried the to-do *"When issue #23 … lands, this sentence and the list
below must be revisited"*; that to-do is now discharged, which is exactly what the issue's fourth
comment required to happen in the same change that removes the binaries.

The two edits touch disjoint line ranges, which is why the merge preserved both.

---

## EVERY CLAIM IN NOTICE AT `cdc6dcb`

18 claims. **17 are factual and all 17 are TRUE**; 1 is an explicit hedge, not a claim.

| # | Line | Claim | Verdict | Basis |
|---|---|---|---|---|
| 1 | 1 | MIT licence in LICENSE covers this repo's own application code only | **TRUE** | `LICENSE` at HEAD is "MIT License / Copyright (c) 2026 Luke Olson" |
| 2 | 2-4 | does not relicense the model files, which remain CC BY-NC-ND 4.0 | **TRUE** | `Registry::LICENSE` == `CC-BY-NC-ND-4.0` |
| 3 | 4-5 | does not relicense Essentia, distributed under AGPL-3.0 | **TRUE** | Essentia is AGPLv3 |
| 4 | 5-7 | anyone redistributing/using this repository takes on the model and Essentia licences independently of MIT | **TRUE** | see O2 for a scope nuance, not a falsehood |
| 5 | 9-10 | CC BY-NC-ND 4.0 and AGPL-3.0 URIs | **TRUE** | canonical creativecommons.org and gnu.org URLs |
| 6 | 12-13 | Essentia invoked as a separate subprocess; **not linked into** the application | **TRUE** | gem shells out to a Python subprocess; "or bundled with" correctly removed |
| 7 | 13-14 | essentia-tensorflow **version 2.1b6.dev1389**, AGPL-3.0, installed into the deployed image at **/usr/local/essentia-venv** | **TRUE** | `Dockerfile:29` pins `essentia-tensorflow==2.1b6.dev1389`; `:28` creates `/usr/local/essentia-venv`; base stage, inherited by the final stage. Version and path match **exactly**. See O1 on completeness |
| 8 | 15-16 | "architectural fact … not a legal opinion" | hedge, not a claim | — |
| 9 | 18-19 | the six files were previously redistributed as tracked objects in git history **and remain in that history** | **TRUE** | 6 `.pb` blobs reachable from `--all` |
| 10 | 19-20 | no longer present in the working tree | **TRUE** | 0 tracked `.pb` at `cdc6dcb` |
| 11 | 20-21 | as of #23 fetched at image build time from essentia.upf.edu | **TRUE** | `Dockerfile:62`; all six registry `source_url`s are on essentia.upf.edu |
| 12 | 21-22 | baked into the final Docker image (**/usr/local/essentia-models/**) | **TRUE** | `Dockerfile:86` COPY; `:38` sets that path |
| 13 | 22 | not committed to the working tree | **TRUE** | loose phrasing (one commits to a repo, not a working tree) but meaning clear and correct; redundant with #10, harmless |
| 14 | 23-24 | attribution obligations survive removal — the bytes were distributed here | **TRUE** | and the right thing to say |
| 15 | 26-27 | Creator: MTG, Universitat Pompeu Fabra; base URL essentia.upf.edu/models/ | **TRUE** | matches `Registry::ATTRIBUTION` verbatim |
| 16 | 29-45 | six entries: filename, historical git path, source URL | **TRUE** | 6/6 filenames == registry; 6/6 URLs == registry `source_url`; 6/6 historical paths == what was actually tracked at `5c9dfcc` |
| 17 | 47-50 | MTG pages conflict SA/ND; CC BY-NC-ND 4.0 is the compliance floor; no per-model variation claimed; application is non-commercial | **TRUE as far as I can verify** — the non-commercial characterisation is the owner's own, stated to you 2026-08-14 |
| 18 | 52-53 | operators responsible for reviewing licences | disclaimer, not a claim | — |

### THE FOUR STATES — all four stated, all four kept distinct

This was the crux, and it is clean:

| State | Where the NOTICE says it | Correct? |
|---|---|---|
| 1. git **HISTORY** — the six `.pb` blobs, still there | `:18-19` "remain in that history" | ✓ 6 blobs reachable |
| 2. **TRACKED TREE** — nothing | `:19-20`, `:22` "no longer present" / "not committed" | ✓ 0 tracked `.pb` |
| 3. deployed **IMAGE** — models **and** essentia-tensorflow, at two different paths | `:21-22` `/usr/local/essentia-models/`; `:13-14` `/usr/local/essentia-venv` | ✓ both disclosed, paths distinct and both verified against the Dockerfile |
| 4. what **MIT** covers — this repo's own code only | `:1` | ✓ |

**The defect shape that bit this file twice is now closed on both axes.** Round 1 caught it for the
models ("not redistributed in deployable artefacts"); round 2 caught it for Essentia ("not bundled
with the application"). At this HEAD both are stated affirmatively, with paths, and neither sentence
is true-of-the-repo-but-false-of-the-image. There is no remaining sentence in the file that asserts
absence from the image.

---

## README `## Licences` — CONSISTENT, NO CONTRADICTION

README `:170-177` at `cdc6dcb`:

> This application is MIT-licensed. See [LICENSE](LICENSE).
>
> The Essentia model files used by this application are CC BY-NC-ND 4.0 and are fetched at image
> build time from essentia.upf.edu. Essentia itself is AGPL-3.0. See [NOTICE](NOTICE) for full
> attribution, licence URIs, and per-model source URLs.

| README statement | NOTICE counterpart | Consistent? |
|---|---|---|
| application is MIT-licensed | `:1` | ✓ |
| model files are CC BY-NC-ND 4.0 | `:2-4` | ✓ |
| fetched at image build time from essentia.upf.edu | `:20-21` | ✓ |
| Essentia itself is AGPL-3.0 | `:4-5`, `:13-14` | ✓ |
| NOTICE has attribution, licence URIs, per-model source URLs | `:9-10`, `:26-27`, `:29-45` | ✓ all three actually present |

**No contradiction.** The replaced sentence — *"This repository redistributes Essentia model
binaries"* — was true on `origin/main` (they were tracked) and would have become misleading about the
tracked tree, so removing it was correct.

README is a summary that omits the image-baking and the git-history retention, but it explicitly
defers to NOTICE for the full picture. Omission is not contradiction, and I am not treating it as a
finding. Noted as O2 only because a reader of README alone gets a slightly rosier picture than the
NOTICE gives.

---

## OBSERVATIONS (non-blocking, both inherited from `origin/main`, neither is #23's)

### O1 — the essentia-tensorflow disclosure names only AGPL-3.0; the wheel also carries TensorFlow (Apache-2.0)

NOTICE `:13-14` describes the distribution as "AGPL-3.0". That is the correct **compliance floor** for
Essentia and matches how the file treats the models, so **it is not a false statement**. The gap is
completeness: `essentia-tensorflow` exists as a separate wheel precisely because it carries TensorFlow
support, and TensorFlow is Apache-2.0, which has its own attribution/NOTICE-propagation expectation.
No separate `tensorflow` pip package is installed at `Dockerfile:29`, which is consistent with it
being bundled in the wheel.

**I could not verify the wheel's contents** — this machine is arm64 and I did not build the image, so
whether TensorFlow is statically bundled or vendored is BELIEVED, not VERIFIED. Recording it as a
question for whoever owns licence completeness, not as a finding against this branch. The sentence
came from `origin/main` and is untouched by #23.

### O2 — "this repository" framing predates the image disclosure

NOTICE `:5-7` says "Anyone redistributing or using **this repository** takes on the model and Essentia
licences." Since the file now discloses that the **image** carries both the models and
essentia-tensorflow, the obligation-transfer sentence arguably wants to name image recipients too —
someone who pulls the image but never clones the repo is the party most affected. Not false as
written, and inherited from `origin/main`. One-line widening would close it, e.g. "…redistributing or
using this repository, or the images built from it, …".

---

## WHAT I DID NOT VERIFY

- **I did not build the image.** arm64 machine; needs `linux/amd64` plus the Essentia toolchain. So
  claims 7, 11 and 12 are verified against the **Dockerfile instructions** (exact version, exact
  paths, correct stages) rather than against a built image. The instructions are unambiguous.
- **O1's wheel contents** — stated above.
- **The non-commercial characterisation** (claim 17) is the owner's own; not independently verifiable
  by me.
- **Nothing outside NOTICE and README** — Dockerfile, spec paths and `.pb` deletions were confirmed
  byte-identical to the already-approved `6df28b9` and were not re-reviewed, per dispatch.

---

## EVIDENCE

Read-only throughout. No scratch mutation was needed this round.

### Premises

```
$ git log -1 --format='%H parent=%P %ci' cdc6dcb
cdc6dcbc… parent=ff67619232dd43db008f9269555590cdf6d37409  2026-08-14 14:06:14 -0700
$ git rev-parse fix/fetch-models-at-build-time origin/fix/fetch-models-at-build-time
cdc6dcbc8a02be14de1ac19ba4b88f3801ec86ef
cdc6dcbc8a02be14de1ac19ba4b88f3801ec86ef        <- stable, pushed
$ git rev-parse origin/main
ff67619232dd43db008f9269555590cdf6d37409
$ git cat-file -e origin/main:LICENSE && git cat-file -e origin/main:NOTICE
  both present                                   <- #29 merged into main

$ git diff --stat 6df28b9 cdc6dcb -- <#23's own files>
 NOTICE | 6 ++++--
$ git diff --name-only origin/main cdc6dcb -- docs/ spec/models/
  (empty)                                        <- the other 27 diffs are inherited

$ git diff --numstat origin/main cdc6dcb -- NOTICE README.md LICENSE
13	10	NOTICE
6	3	README.md
                                                 <- LICENSE inherited; NOTICE/README are #23's
```

### The merge preserved both halves

From `origin/main`, N1 discharged (`NOTICE:12-16`):

```
Essentia is invoked as a separate subprocess at runtime; it is not linked into
the application. The essentia-tensorflow distribution (version 2.1b6.dev1389,
AGPL-3.0) is installed into the deployed image at /usr/local/essentia-venv.
```

From #23, the to-do discharged — `git diff origin/main cdc6dcb -- NOTICE`:

```diff
-The following model files are currently tracked in this repository. When issue
-#23 (remove vendored model binaries from the tracked tree) lands, this sentence
-and the list below must be revisited — at that point the files will ship via a
-download step at build or runtime, not as committed objects.
+The following six model files were previously redistributed as tracked objects in
+this repository's git history and remain in that history. They are no longer
+present in the working tree; as of issue #23 they are fetched at image build
+time from essentia.upf.edu and are baked into the final Docker image
+(/usr/local/essentia-models/). They are not committed to the working tree.
+Attribution obligations for these files survive their removal from the working
+tree — the bytes were distributed here.
```

### Facts each claim rests on

```
$ git show cdc6dcb:LICENSE | head -3
MIT License
Copyright (c) 2026 Luke Olson

$ git show cdc6dcb:Dockerfile | grep -n "essentia-venv\|essentia-tensorflow\|essentia-models"
28:    python3 -m venv /usr/local/essentia-venv && \
29:    /usr/local/essentia-venv/bin/pip install --no-cache-dir "essentia-tensorflow==2.1b6.dev1389" "yt-dlp" && \
31:ENV PATH="/usr/local/essentia-venv/bin:${PATH}"
38:    ESSENTIA_MODELS_DIR="/usr/local/essentia-models" \
86:COPY --chown=rails:rails --from=build /usr/local/essentia-models /usr/local/essentia-models

  tracked .pb at cdc6dcb:            0
  .pb blobs reachable in history:    6
```

### The list, derived against the gem registry (not transcribed)

```
registry=6 listed=6 urls=6 historical_paths=6
filenames == registry?              true
urls match registry source_url?     true

registry LICENSE constant: CC-BY-NC-ND-4.0
registry ATTRIBUTION:      Music Technology Group, Universitat Pompeu Fabra — https://essentia.upf.edu/models/
```

Historical paths claimed by the NOTICE, checked against what was actually tracked at the old base:

```
$ git ls-tree -r --name-only 5c9dfcc -- tmp/essentia_models
tmp/essentia_models/danceability-msd-musicnn-1.pb
tmp/essentia_models/emomusic-msd-musicnn-2.pb
tmp/essentia_models/mood_acoustic-msd-musicnn-1.pb
tmp/essentia_models/mood_happy-msd-musicnn-1.pb
tmp/essentia_models/mood_relaxed-msd-musicnn-1.pb
tmp/essentia_models/msd-musicnn-1.pb
```

All six match the `(was … in git history)` annotations exactly.

### Repo state

Read-only. No edits, no commits, no staging, nothing pushed. Both repositories remain on their
original branches.

---

## SUMMARY

**APPROVE on NOTICE and README at `cdc6dcb`.**

- All 17 factual claims in NOTICE are true; the 18th is an explicit hedge.
- All four states — history, tracked tree, image, MIT scope — are stated and kept distinct. The
  true-of-the-repo/false-of-the-image defect shape is closed on **both** axes for the first time.
- Neither half of the merge was lost: N1's AGPL disclosure and #23's model correction coexist in
  disjoint paragraphs.
- README is consistent with NOTICE and contradicts nothing.
- O1 and O2 are non-blocking completeness points, both inherited from `origin/main`, neither
  introduced by #23. Route to a licence-completeness follow-up if you want them closed; they do not
  gate this merge.
