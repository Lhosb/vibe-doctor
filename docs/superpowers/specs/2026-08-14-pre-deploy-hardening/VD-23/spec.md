# SPEC REVIEW — vibe-doctor issue #23 (TIER 1) — requirement conformance

**VERDICT: REQUEST-CHANGES** — 1 HIGH, 3 MEDIUM, 1 LOW. The five-part design is structurally
implemented, but one part of the accepted design's *stated property* is not delivered, one sentence
of the NOTICE is false, and two model-path readers were missed.

- REPO: `/Users/lukeolson/projects/vibe-doctor`
- BASE_SHA: `5c9dfccda17ccf26af5267d099a391e3b2e882a8` (origin/main)
- HEAD_SHA: `24e17798dc386d794c8dc032360a31e754350e33`
- BRANCH: `fix/fetch-models-at-build-time` (not pushed), worktree `.worktrees/fetch-models-at-build-time`
- Diff range: `git diff 5c9dfcc...24e1779`
- Discipline: **requirement conformance only.** Security → Warden, test → Litmus.
- Implementer report read in full, **including the appended CORRECTION**, before reviewing.

Files in range (12): six `.pb` deleted; `.dockerignore`, `.gitignore`, `Dockerfile`, `README.md`
modified; `LICENSE`, `NOTICE` added. No `deploy.yml`, no `.kamal/hooks`, no `Gemfile*`.

---

## PREMISE CORRECTION — please re-read before weighing Q3

Your Q3 states: *"origin/main carries a root NOTICE from issue #29."* **It does not.**

```
$ git show origin/main:NOTICE
fatal: path 'NOTICE' does not exist in 'origin/main'
$ git cat-file -e origin/main:LICENSE  -> ABSENT
$ git show origin/main:README.md | grep -c '## Licences'  -> 0
$ git merge-base --is-ancestor origin/fix/model-attribution-notice origin/main
  NO — not an ancestor of origin/main
```

The NOTICE lives only on the **unmerged** branch `origin/fix/model-attribution-notice`. In the
reviewed range `NOTICE` and `LICENSE` are status `A` (added), not `M`. This does not soften Q3 — it
sharpens it, and it drives **F4**: this branch does not *correct* #29's NOTICE, it **re-creates all
of #29 independently**, which is what makes the merge conflict inevitable.

---

## 1. THE FIVE-PART ACCEPTED DESIGN, ONE BY ONE

| # | Accepted design | Status | Evidence |
|---|---|---|---|
| 1 | Remove binaries from tracked tree | **MET** | `git ls-files -- '*.pb'` → `0`; 6 × `D` in diff; blobs remain in history (no rewrite) |
| 2 | Fetch at build time via gem CLI into `/usr/local/essentia-models` | **MET (placement defective — F1)** | `Dockerfile:71` in the `build` stage (`FROM base AS build`, `:42`) |
| 3 | Verify in FINAL stage as uid 1000 | **MET** | `Dockerfile:89`, final stage (`FROM base`, `:75`), after `USER 1000:1000` (`:80`) |
| 4 | Point the app at the new location | **PARTIAL — F3** | ENV at `Dockerfile:38`; all four production sites inherit it; **two other readers missed** |
| 5 | No volume / no Kamal hook / no gem change | **MET** | no `deploy.yml`, `.kamal/`, or `Gemfile*` in the diff; `deploy.yml:78-79` still the single storage volume; all hooks `.sample` |

Part 3's **ordering** really is correct: `USER 1000:1000` at `:80` precedes the verify `RUN` at `:89`,
and `COPY --chown=rails:rails` at `:85` sets ownership. That is the part that was easiest to get wrong
and it is right.

> **CORRECTION (appended after dispatcher feedback).** My first pass said the gate "validates digests,
> ownership and mode as the runtime user." **That was too generous** — see **F6**, where I establish
> by execution exactly what `verify` does and does not enforce. The dispatcher also relays that three
> reviewers flagged it as "digest only — no ownership or mode check exists"; **that is too strong in
> the other direction.** The precise answer is in F6.

Part 5 is clean — I looked for a volume mounted over the models path and there is none; the only
volume is `vibe_doctor_storage:/rails/storage`, which cannot shadow `/usr/local/essentia-models`.

---

## 2. THE FOUR `models_dir` SITES — DERIVED, NOT TRANSCRIBED

I did not use the implementer's list. I swept the whole repo (not just `app/ lib/`) for `models_dir`,
`ESSENTIA_MODELS_DIR`, `SONANCE_MODELS_DIR`, and the path literal.

**Production, env-driven — exactly FOUR. The count is correct.**

| # | Site | Picks up new path? |
|---|---|---|
| 1 | `app/jobs/enrich_album_job.rb:6` | yes — `ENV.fetch("ESSENTIA_MODELS_DIR", …)` |
| 2 | `app/services/mood_grounding_service.rb:11` | yes |
| 3 | `lib/tasks/enrichment.rake:19` | yes |
| 4 | `lib/tasks/enrichment.rake:32` | yes |

All four resolve via `ESSENTIA_MODELS_DIR="/usr/local/essentia-models"` at `Dockerfile:38`, set in
the **base** stage, which both `build` and the final stage inherit. Confirmed no Ruby change needed.

`SONANCE_MODELS_DIR` — the env var the *gem CLI* reads — appears **nowhere** in the app. That is why
`Dockerfile:71` and `:89` pass `--models-dir` explicitly. Correct as written; worth knowing the two
variables are not the same name, so setting only `ESSENTIA_MODELS_DIR` would not steer the CLI.

**But the sweep found two more readers that hardcode the old path** — see **F3**. The implementer's
stated command was scoped to `app/ lib/`, which structurally cannot reach them:

```
$ grep -rn "models_dir\|ESSENTIA_MODELS_DIR" app/ lib/ --include="*.rb"     # their command
app/jobs/enrich_album_job.rb:6: …
app/services/mood_grounding_service.rb:11: …
```

Note their stated command returns **two** results, not the four they report — `--include="*.rb"`
cannot match `enrichment.rake`. The *answer* is right; the command shown does not produce it.

---

## 3. IS THE NOTICE AT HEAD TRUE?

Judged sentence by sentence against what I verified.

| NOTICE claim | Verdict |
|---|---|
| `:16-17` "previously redistributed as tracked objects in this repository's git history and remain in that history" | **TRUE** — tracked on `origin/main`, `git rm --cached` only, no rewrite |
| `:17-18` "no longer present in the working tree" | **TRUE for any recipient** — a fresh clone has none. (They remain on disk in the implementer's own worktree, a local artefact of `--cached`, not part of the distribution.) |
| `:18` "as of this commit they are fetched at image build time from essentia.upf.edu" | **TRUE** — `Dockerfile:71` |
| `:19` **"and are not redistributed in deployable artefacts"** | **FALSE — see F2** |
| `:20-21` "Attribution obligations … survive their removal — the bytes were distributed here" | **TRUE, and the right call** — this is exactly the sentence that keeps the NOTICE honest about history |

So it is **neither** of the two failure modes you named: it does not claim they were never distributed
here, and it does not claim they are still in the tree. Both of those traps were avoided. The
falsehood is a third one — a claim about the **image**, not about the tree or the history.

---

## FINDINGS

### F1 — HIGH — the fetch layer does **not** cache on `Gemfile.lock`; every code-only deploy refetches

**`Dockerfile:68-71`** (comment and `RUN`).

The comment asserts: *"This layer caches on Gemfile.lock, so code-only deploys never refetch."* The
accepted design leans on exactly this to bound the new dependency:

> "Bounded, because previously built images still deploy and roll back, and the fetch layer caches on
> Gemfile.lock, so code-only deploys never refetch."

**The fetch `RUN` is at `:71`, after `COPY . .` at `:59`.** Docker invalidates every layer following
an invalidated one, and `COPY . .` invalidates on *any* change in the build context. So the fetch
re-runs on every code change. It caches on the whole application tree, not on `Gemfile.lock`.

Proven with a synthetic pair plus a passing control (full output in Evidence). On a code-only edit
with `Gemfile.lock` untouched:

- **as-implemented ordering** (fetch after `COPY . .`) → fetch layer **re-executes**
- **control** (fetch before `COPY . .`) → fetch layer **`CACHED`**

**Failure scenario:** every routine code deploy now makes a hard build-time dependency on
`essentia.upf.edu` — an academic host with no SLA, which the design accepted *only* because it was
believed to be hit rarely. If it is down during any ordinary deploy, the build fails. The risk
accepted and the risk shipped are different risks.

**Fix:** move the fetch to immediately after the `bundle install` block (`:53-56`), before
`COPY . .`. It depends on the gem, not on application code. Then the comment becomes true.

### F2 — MEDIUM — `NOTICE:19` states the models are "not redistributed in deployable artefacts". The image contains them.

**`NOTICE:18-19`**, contradicted by **`Dockerfile:85`**.

```
NOTICE:19   … and are not redistributed in deployable artefacts.
Dockerfile:85  COPY --chown=rails:rails --from=build /usr/local/essentia-models /usr/local/essentia-models
```

The container image **is** the deployable artefact, and the whole point of the design is that the six
models are baked into it — which is why runtime needs no network and why the implementer's
`--network none` verify passes with 6 `.pb` present. Whatever else changed, the models are still
shipped inside the thing that gets pushed to a registry and deployed.

**Failure scenario:** a public repository's licence NOTICE asserts non-redistribution of
CC-BY-NC-ND material in the artefact that in fact redistributes it. This is the single sentence in
the file that has to be true, and it is the one that is false. It also *weakens* the correct
statement two lines below it (`:20-21`), by implying the surviving obligation is historical only.

**Fix:** replace with something like — *"they are fetched at image build time from essentia.upf.edu
and are included in the built container image; attribution obligations therefore apply to the image
as well as to this repository's history."*

### F3 — MEDIUM — two model-path readers were not repointed; the documented golden procedure breaks

**`spec/integration/essentia_extract_golden_spec.rb:19`** — `MODELS_DIR = ROOT.join("tmp/essentia_models")`
**`spec/fixtures/sonance/generate_goldens.rb:9`** — `models_dir = root.join("tmp/essentia_models")`

Both hardcode the old path and neither reads `ESSENTIA_MODELS_DIR`. After this change that directory
is empty for any recipient and absent from the build context:

- `git ls-files -- '*.pb'` → `0`; `git check-ignore` → ignored by `.gitignore:16 /tmp/*`
- `.dockerignore:19 /tmp/*` with the negations removed → not in the build context at all

The golden spec's own header (`:6-14`) documents running it **inside an image built from this
Dockerfile**, where `/rails/tmp/essentia_models` will now be empty while the models sit at
`/usr/local/essentia-models`.

**Failure scenario:** the next person to regenerate or verify goldens follows the documented
procedure and gets `missing model: /rails/tmp/essentia_models/msd-musicnn-1.pb`. This is the app's
**only** real-Essentia gate.

**Why nothing caught it:** the spec is tagged `:essentia` and excluded unless `ESSENTIA_SPECS=1`
(`spec/spec_helper.rb:17`), so it is not in the 298. And the suite passed locally only because
`git rm --cached` left the six files on disk in that worktree — a fresh clone would not have them.
A green 298/0 is compatible with this being broken.

**Fix:** one line each — `ENV.fetch("ESSENTIA_MODELS_DIR", ROOT.join("tmp/essentia_models"))`,
matching the four production sites.

### F4 — MEDIUM — the branch delivers all of issue #29, which #23 explicitly said it must not

`LICENSE`, `NOTICE`, and the README `## Licences` section are all **added** here, and none exists on
`origin/main`. Issue #23's own second comment recorded the opposite intent:

> "Filed separately as a distinct issue, because it is a compliance matter with different urgency
> from deploy mechanics and **should not be closed as a side effect of this one.**"

The fourth comment scopes #23 to *correcting* a NOTICE it assumes #29 has already landed ("the NOTICE
must be corrected in the same change that removes the binaries"). Because #29 is unmerged, the
implementer re-created it instead. That is a defensible response to an unmet precondition, but it is
a deviation from a recorded decision and it was not flagged — the implementer report presents
LICENSE/NOTICE/README as ordinary in-scope work.

**Concrete consequence, demonstrated:** merging the two branches conflicts.

```
CONFLICT (add/add): Merge conflict in NOTICE
CONFLICT (content): Merge conflict in README.md
```

`LICENSE` is byte-identical and auto-merges. Someone must resolve NOTICE and README by hand, and the
correct resolution is HEAD's side in both — which means #29's branch has been silently superseded
rather than merged. **Routing that is your call:** either land #29 first and rebase this to a
correction-only diff, or close #29 as superseded and say so explicitly. It should not be left implicit.

### F5 — LOW — the NOTICE file list was not revised, though the flagged text said it must be

The paragraph this change replaces said *"this sentence **and the list below** must be revisited."*
The sentence was revised; **the list was not.** `NOTICE:26-42` still labels the six entries with
`tmp/essentia_models/…` paths and does not mention `/usr/local/essentia-models`.

Defensible as a historical reference — the new framing at `:16-19` does establish the list as
past-tense — so this is LOW, not a correctness bug. But it leaves the file describing only where the
bytes *used to* be, and combined with F2 the NOTICE never states where they are now.

### F6 — LOW — `Dockerfile:87-88` overclaims what `verify` enforces, but less than the consensus says

**`Dockerfile:87-88`**: *"Verify model digests, ownership, and mode as the runtime user."*

I established the actual enforcement by execution against `ModelStore#verify!`, with a passing
control at both ends (full output in Evidence). The call chain is
`verify!` → `verify_model!` → `Files#digest` → `path_for` → `misconfiguration_checked_root` →
`detect_root_misconfiguration!` (`lib/sonance/model_store.rb:105-153`), so the root checks **do** run
on the verify path.

| Perturbation | Result |
|---|---|
| control: dir `0700`, file `0644`, digest correct | **PASS** |
| **directory** `0777` group/world-writable | **RAISE** — "must not be group- or world-writable" |
| directory `0750` (group-readable, not writable) | PASS — correctly permitted |
| **model file** `0666` world-writable, directory clean | **PASS — not detected** |
| model file byte-corrupted | RAISE — "model digest mismatch" |
| model file missing | RAISE — "missing model" |
| model file replaced by symlink to a correct-digest copy | RAISE — "model path must not be a symlink" |
| re-control: restored | **PASS** |

**So both characterisations are wrong.** Ownership and mode *are* enforced — on the models
**directory** (uid must equal euid; no group/world-write). They are *not* enforced on the individual
model **files**: a world-writable `.pb` with a correct digest passes. Files get digest, presence,
regular-file and anti-symlink checks.

The comment is therefore a **mild** overclaim — true of the directory, false if read as covering the
model files — not the "digest only" gutting the consensus suggests. Running as uid 1000 is doing real
work: the directory ownership check is evaluated against the runtime euid, so it could not have been
satisfied by a root-owned directory.

**Practical impact is low**: `COPY --chown=rails:rails` sets `rails:rails` and image layers do not
produce world-writable files by default, so the unchecked axis is unlikely to be violated. This is a
comment-accuracy fix, not a security hole — one line, e.g. *"Verify model digests and the models
directory's ownership and mode, as the runtime user."*

I am rating this LOW and flagging that **F6 belongs to Warden's discipline more than mine**; I
verified it only because I had asserted something stronger and needed to correct my own claim.

### Observation (not rated) — leftover blank lines

`.gitignore` and `.dockerignore` each removed three lines but left the surrounding blank line, giving
a double blank at `.dockerignore:32-33` and `.gitignore:31-32`. Cosmetic; no behavioural effect.

---

## 5. ANYTHING IN THE DIFF NOT REQUIRED BY THE ISSUE

Only **F4** (LICENSE + NOTICE + README, i.e. all of #29). Everything else maps to the accepted design.
No gold-plating: no volume, no hook, no retry logic, no gem change, no Ruby source change, no test
changes. The Dockerfile edits are exactly the three the design calls for.

---

## ON TRAP 2 — the sabotage pair (brief; discriminating-power depth is Litmus's)

Two things, from a conformance angle.

**The specified proof was not run as specified.** The accepted design says apply the *same* sabotage
(delete the `.dockerignore` negations) to both. The implementer ran OLD with that sabotage but
substituted a **different** NEW-side sabotage — delete one model between fetch and verify.

**I judge the substitution correct, and I would not ask them to redo it.** Deleting the negations is a
*no-op* for NEW: NEW does not receive models through the build context at all, so applying it would
sabotage nothing and prove nothing. A negative control has to perturb the mechanism actually in use.
Their substitute perturbs exactly the new guard, and the pair does discriminate on what matters —
OLD produces a working-looking image that fails at first enrichment, NEW fails at build with no image:

| Config | Build exit | `.pb` in image | Fails when |
|---|---|---|---|
| OLD, negations removed | 0 | 0 | first enrichment |
| NEW, model removed pre-verify | 1 | no image | build time |

**The gap:** the scenario closest to OLD's real failure — *the fetch itself not producing models*
(host unreachable, empty response) — was never run. By construction `sonance models fetch` raises and
the build fails, but that is reasoning, not evidence, and F1 makes that path far more frequently
travelled than the design assumed. Worth one `--network none` build. Flagging for Litmus.

---

## WHAT I COULD NOT VERIFY

- **I did not build the real image.** This machine is **arm64**; the image needs `linux/amd64` and
  `essentia-tensorflow`, and the remote builder is not mine to drive. So F2's "the image contains the
  models" rests on `Dockerfile:85` (unambiguous) plus the implementer's own build evidence, not on my
  own build. I consider the mechanism certain and the observation second-hand, and say so rather than
  implying I ran it.
- **I did not re-run the 298-example suite.** You state you re-ran it and confirm 298/0, and it is
  Litmus's remit. My F3 is not contradicted by a green suite — I explain above why the two are
  compatible.
- **I did not test builder egress.** Confirmed by the owner, recorded in the issue.
- **Whether `/usr/local/essentia-models` mode/ownership is exactly as expected in the final image** —
  that is Warden's, and it needs a real build.

---

## EVIDENCE

Read-only throughout. The cache demonstration and the merge test both ran in scratch directories
**outside both repositories**:
`…/114a28aa-a39b-4f12-b984-096f60d7375d/scratchpad/vd23-cache` and `…/scratchpad/vd23merge`.

### Diff range and scope

```
$ git -C /Users/lukeolson/projects/vibe-doctor diff --name-status 5c9dfcc...24e1779
M	.dockerignore
M	.gitignore
M	Dockerfile
A	LICENSE
A	NOTICE
M	README.md
D	tmp/essentia_models/danceability-msd-musicnn-1.pb
D	tmp/essentia_models/emomusic-msd-musicnn-2.pb
D	tmp/essentia_models/mood_acoustic-msd-musicnn-1.pb
D	tmp/essentia_models/mood_happy-msd-musicnn-1.pb
D	tmp/essentia_models/mood_relaxed-msd-musicnn-1.pb
D	tmp/essentia_models/msd-musicnn-1.pb
12 files changed, 90 insertions(+), 7 deletions(-)

$ git diff --name-only 5c9dfcc...24e1779 | grep -E 'deploy\.yml|\.kamal|Gemfile'
  NONE — no volume, no hook, no gem change
```

### Design parts 1-3: the Dockerfile as shipped

```
 38	    ESSENTIA_MODELS_DIR="/usr/local/essentia-models" \      <- base stage ENV
 42	FROM base AS build
 53	RUN bundle install && \                                     <- caches on Gemfile.lock
 59	COPY . .                                                    <- invalidates on ANY code change
 63	RUN bundle exec bootsnap precompile -j 1 app/ lib/
 66	RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile
 68	# Fetch Essentia mood models into a dedicated directory. This layer caches on
 69	# Gemfile.lock, so code-only deploys never refetch. …                     <- F1: false
 71	RUN bundle exec sonance models fetch --models-dir /usr/local/essentia-models
 75	FROM base                                                   <- FINAL stage
 80	USER 1000:1000
 85	COPY --chown=rails:rails --from=build /usr/local/essentia-models /usr/local/essentia-models
 89	RUN bundle exec sonance models verify --models-dir /usr/local/essentia-models
```

Part 3 confirmed: `:89` follows `:80`, in the stage beginning at `:75`.

### Part 1: binaries gone, blobs retained, out of the build context

```
$ git ls-files -- '*.pb' | wc -l
0
$ git check-ignore -v tmp/essentia_models/msd-musicnn-1.pb
.gitignore:16:/tmp/*	tmp/essentia_models/msd-musicnn-1.pb
$ grep -n tmp .dockerignore
19:/tmp/*        <- negations at old :34-35 removed; no re-inclusion
$ ls tmp/essentia_models/     # still on disk in THIS worktree — why the local suite is green
danceability-msd-musicnn-1.pb  emomusic-msd-musicnn-2.pb  … msd-musicnn-1.pb   (6 files)
```

### F1 — Docker layer cache, discriminating pair with a passing control

Both images primed, then a **code-only** edit with `Gemfile.lock` untouched:

```
===== AS-IMPLEMENTED (fetch after COPY . .) =====
#6 CACHED
#7 CACHED
#8 CACHED
#9 [5/7] COPY . .
#11 [7/7] RUN echo "=== SONANCE MODELS FETCH (network) ===" && date +%s%N > /fetch_stamp
#11 0.123 === SONANCE MODELS FETCH (network) ===          <- RE-RAN

===== CONTROL: fetch before COPY . . =====
#6 CACHED
#7 CACHED
#8 CACHED
#9 [5/7] RUN echo "=== SONANCE MODELS FETCH (network) ===" && date +%s%N > /fetch_stamp
#9 CACHED                                                  <- STAYED CACHED
#10 [6/7] COPY . .
```

The control is the point: the same edit leaves the fetch cached when it precedes `COPY . .`, so the
difference is the ordering and nothing else.

### Q2 — derived site list

```
$ grep -rn "models_dir" --include='*.rb' --include='*.rake' --include='*.yml' --include='*.erb' .
app/jobs/enrich_album_job.rb:6:      models_dir: ENV.fetch("ESSENTIA_MODELS_DIR", …)
app/services/mood_grounding_service.rb:11:      models_dir: ENV.fetch("ESSENTIA_MODELS_DIR", …)
lib/tasks/enrichment.rake:19:      models_dir: ENV.fetch("ESSENTIA_MODELS_DIR", …)
lib/tasks/enrichment.rake:32:    models_dir: ENV.fetch("ESSENTIA_MODELS_DIR", …)
spec/integration/essentia_extract_golden_spec.rb:35:  let(:extractor) { Sonance::Extractor.new(models_dir: MODELS_DIR) }
spec/fixtures/sonance/generate_goldens.rb:9:models_dir = root.join("tmp/essentia_models")
… (spec/ mktmpdir sites — self-contained, not path-dependent)

$ grep -rn "SONANCE_MODELS_DIR" .        # the CLI's own env var
  (none)
```

### F3 — the two missed readers and why the suite stays green

```
$ grep -rn "tmp/essentia_models" spec/ --include='*.rb'
spec/integration/essentia_extract_golden_spec.rb:19:  MODELS_DIR = ROOT.join("tmp/essentia_models")
spec/fixtures/sonance/generate_goldens.rb:9:models_dir = root.join("tmp/essentia_models")

$ grep -n filter_run_excluding spec/spec_helper.rb
17:  config.filter_run_excluding essentia: true unless ENV["ESSENTIA_SPECS"] == "1"

$ sed -n '15p' spec/integration/essentia_extract_golden_spec.rb
RSpec.describe "Essentia extraction goldens", :essentia do
```

### Q3/Q4 — NOTICE state and drift

```
$ git show origin/main:NOTICE
fatal: path 'NOTICE' does not exist in 'origin/main'
$ git merge-base origin/fix/model-attribution-notice 24e1779
5c9dfccda17ccf26af5267d099a391e3b2e882a8          <- both branch off origin/main

$ git diff origin/fix/model-attribution-notice 24e1779 -- LICENSE
                                                   <- empty: identical, no drift

$ git diff origin/fix/model-attribution-notice 24e1779 -- NOTICE
-The following model files are currently tracked in this repository. When issue
-#23 … this sentence and the list below must be revisited …
+The following six model files were previously redistributed as tracked objects
+in this repository's git history and remain in that history. They are no longer
+present in the working tree; as of this commit they are fetched at image build
+time from essentia.upf.edu and are not redistributed in deployable artefacts.
+Attribution obligations for these files survive their removal from the working
+tree — the bytes were distributed here.
```

Drift is confined to exactly the flagged paragraph (plus a README rewrite). Nothing else in NOTICE
moved; the per-model list and URLs are unchanged between branches.

### F4 — merge conflict, demonstrated in a scratch clone

```
$ git checkout 24e1779 -b test-23 && git merge --no-commit --no-ff origin/fix/model-attribution-notice
Auto-merging NOTICE
CONFLICT (add/add): Merge conflict in NOTICE
Auto-merging README.md
CONFLICT (content): Merge conflict in README.md
Automatic merge failed; fix conflicts and then commit the result.

$ git diff --name-only --diff-filter=U
NOTICE
README.md
```

### F6 — what `sonance models verify` actually enforces (synthetic registry, real ModelStore)

A synthetic one-model registry was used so no real weights were needed. Controls at both ends:

```
=== CONTROL: dir 0700, file 0644, digest correct ===
  verify!: PASS — no raise
=== DIRECTORY 0777 (group/world-writable), file untouched ===
  verify!: RAISE Sonance::ConfigurationError — models directory misconfiguration: must not be group- or world-writable
=== DIRECTORY 0750 (group-readable, not writable) ===
  verify!: PASS — no raise
=== MODEL FILE 0666 world-WRITABLE, directory clean ===
  file mode: 0666
  verify!: PASS — no raise                      <- file mode NOT enforced
=== MODEL FILE byte-corrupted ===
  verify!: RAISE Sonance::ConfigurationError — model digest mismatch: fake-model-1.pb
=== MODEL FILE missing ===
  verify!: RAISE Sonance::ConfigurationError — missing model: …
=== MODEL FILE replaced by a symlink to a correct-digest copy ===
  verify!: RAISE Sonance::ConfigurationError — model path must not be a symlink: …
=== RE-CONTROL: restored, must PASS again ===
  verify!: PASS — no raise
```

### Note on the worktree's on-disk models

When I first inspected, `.worktrees/fetch-models-at-build-time/tmp/essentia_models/` still held all
six `.pb` files on disk (the residue of `git rm --cached`), and I cited that as the reason the local
suite stays green. **That directory has since been removed** — it no longer exists. HEAD is unchanged
at `24e1779` and the worktree is still clean. This does not alter any finding; it strengthens **F3**,
since the old path is now empty locally as well as in a fresh clone. I did not remove it.

### Repo state

Read-only. No edits, no commits, no staging, nothing pushed. The implementer's worktree was only read
and `grep`ed. Both mutation experiments ran in scratch directories outside both repositories.

---

## SUMMARY FOR THE DISPATCHER

Issue #23 must **not** be closed on this commit as it stands — not because the build-time fetch is
missing (it is present and correctly gated in the final stage as uid 1000), but because:

- **F1** means the accepted risk bound does not hold as shipped — one-line ordering fix.
- **F2** means the licence NOTICE contains a false statement about the artefact — one-sentence fix.
- **F3** means the only real-Essentia verification path is silently broken — one line each in two files.
- **F4** is a routing decision for you, not a code fix.

None of the four is architectural. F1–F3 are small, local edits; the design itself is sound and parts
1, 2, 3 and 5 are correctly implemented.
