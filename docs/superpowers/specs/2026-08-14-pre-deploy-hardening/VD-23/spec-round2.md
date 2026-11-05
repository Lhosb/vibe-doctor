# SPEC RE-REVIEW ROUND 2 — vibe-doctor issue #23 (TIER 1) — requirement conformance

**VERDICT: APPROVE.** All six of my round-1 findings (F1–F6) are closed. One new observation from
the claim-by-claim NOTICE walk is **inherited from #29, not introduced by #23**, and is reported for
routing rather than as a blocker on this branch.

- REPO: `/Users/lukeolson/projects/vibe-doctor`
- **HEAD ACTUALLY REVIEWED: `6df28b9c464236d764674cf26182945b679be381`** — see the SHA correction below
- BASE: `a046b69` (tip of `origin/fix/model-attribution-notice`)
- Review range: `git diff a046b69...6df28b9`
- Round 1 report: `/tmp/maestri-reviews/VD-23/spec.md`
- Discipline: requirement conformance only.

---

## ⚠️ SHA CORRECTION — THE BRANCH MOVED DURING THIS REVIEW. READ THIS FIRST.

Your dispatch contains two different SHAs: *"NEW HEAD: 29c94bb"* and *"exactly ONE unique commit,
6df28b9. I verified that."* **They are different commits with different trees, and the second one is
correct.**

When I began, `fix/fetch-models-at-build-time` pointed at `29c94bb` and so did the worktree. Partway
through, both moved to `6df28b9`:

```
29c94bb  2026-08-14 13:48:12 -0700   tree 6d8d8e6b…
6df28b9  2026-08-14 13:53:06 -0700   tree 6da67ffb…      <- LIVE TIP, 5 minutes later
identical commit messages; both parented on a046b69
$ git diff --stat 29c94bb 6df28b9
 Dockerfile | 5 +++--
```

`6df28b9` is a **later amend** of the same commit. `29c94bb` is now unreachable from the branch.

**This is not academic — the delta is load-bearing for F6.** The two commits differ *only* in the
verify comment, and:

- on `29c94bb` (the SHA your dispatch named as HEAD) the comment **underclaims**, and I would have
  filed F6 as still-open;
- on `6df28b9` (the live tip) the comment is **exactly right** and F6 closes.

**I reviewed `6df28b9`.** Everything below refers to it. Please confirm that is the intended HEAD
before acting on this APPROVE — if you meant `29c94bb`, my verdict changes to REQUEST-CHANGES on F6
alone.

---

## FINDING-BY-FINDING

### F1 — HIGH — fetch layer cache ordering → **CLOSED**

`Dockerfile:62`, now placed after the `bundle install` block (`:53-56`) and **before** `COPY . .`
(`:65`). This is structurally the exact ordering I used as the passing control in round 1, which
demonstrated the layer stays `CACHED` on a code-only edit. The comment (`:58-61`) was rewritten to
match: *"depends only on Gemfile.lock (copied above), so code-only deploys leave it cached."*

The implementer additionally ran the pair on the real amd64 builder and reports the fetch layer
`CACHED` on a code-only rebuild. I did not re-run that (arm64), but it agrees with my own control and
with Docker's documented cache semantics.

**Nit, not a finding:** "depends only on Gemfile.lock" is slightly imprecise — the layer also sits
behind `COPY vendor/* ./vendor/` (`:50`) and `COPY Gemfile Gemfile.lock ./` (`:51`). `vendor/` holds
three files, one of which is `vendor/javascript/echarts.js`, so an echarts bump would refetch. That
is a rarely-changed vendored dependency, not routine app code, so the material claim — code-only
deploys leave it cached — holds. Not worth a change.

### F2 — MEDIUM — false "not redistributed in deployable artefacts" → **CLOSED**

`NOTICE:16-22` now reads, in relevant part: *"…as of issue #23 they are fetched at image build time
from essentia.upf.edu **and are baked into the final Docker image (/usr/local/essentia-models/)**.
They are not committed to the working tree."*

This is **true**, and it is the right fix: it does not merely delete the false claim, it affirmatively
discloses that the image redistributes the models. That is what a CC BY-NC-ND notice needs to say.
Claim-by-claim verification in the next section.

### F3 — MEDIUM — hardcoded model-path readers → **CLOSED**

```
spec/integration/essentia_extract_golden_spec.rb:19
  MODELS_DIR = Pathname(ENV.fetch("ESSENTIA_MODELS_DIR", ROOT.join("tmp/essentia_models").to_s))
spec/fixtures/sonance/generate_goldens.rb:9
  models_dir = Pathname(ENV.fetch("ESSENTIA_MODELS_DIR", root.join("tmp/essentia_models").to_s))
```

Both now match the four production sites' pattern, both correctly re-wrap in `Pathname` (the
`ENV.fetch` returns a String, so the wrap is necessary and present). Inside the image
`ESSENTIA_MODELS_DIR` is set at `Dockerfile:38`, so the documented golden procedure resolves to
`/usr/local/essentia-models`. Outside the image the fallback preserves prior behaviour. A repo-wide
grep shows the only remaining occurrences of the literal are these two fallbacks, which is correct.

### F4 — MEDIUM — branch delivered all of #29 → **CLOSED**

Rebased onto `a046b69`. Verified independently:

- `LICENSE` is **absent from the incremental diff** and **present at HEAD** — it now arrives from the
  attribution branch, as intended.
- `a046b69..6df28b9` contains **exactly one commit**.
- **The conflict I demonstrated in round 1 is gone.** Merging the attribution branch into this branch
  reports `Already up to date.` with zero conflicted paths, and the reverse direction
  **fast-forwards** cleanly.

### F5 — LOW — NOTICE model list not revised → **CLOSED**

Entries now name the bare filename with the historical git path in parentheses. I cross-checked the
list against the gem registry by derivation rather than reading: **6/6 filenames match
`Registry.default` exactly, and 6/6 source URLs match each model's `source_url` exactly**, with no
extras in either direction.

### F6 — LOW — verify comment overclaim → **CLOSED on `6df28b9`** (would be open on `29c94bb`)

Live tip `Dockerfile:88-90`:

```
# Verify model digests and the models directory's ownership and mode, as the runtime user.
# (Individual model files: digest, presence, regular-file, and anti-symlink checks.
#  Models directory: uid ownership and write-permission checks.)
```

Checked against the matrix I established by execution in round 1 — every clause is one I verified,
and no enforcement I verified is omitted:

| Comment clause | My verified result |
|---|---|
| files: digest | RAISE on byte-corruption ✓ |
| files: presence | RAISE on missing ✓ |
| files: regular-file / anti-symlink | RAISE on symlink-to-correct-digest ✓ |
| directory: uid ownership | enforced (`uid == Process.euid`) ✓ |
| directory: write permission | RAISE on dir `0777`; PASS on `0750` ✓ |
| "as the runtime user" | the euid comparison is why uid 1000 placement matters ✓ |

**Not stronger, not weaker** — this is precisely your criterion, and it is met. It also restores the
real justification for placing verify after `USER 1000:1000`, which the intermediate `29c94bb`
wording had lost.

---

## THE NOTICE, WALKED CLAIM BY CLAIM AT THIS HEAD

You asked whether **every** sentence is true, with particular attention to the tracked tree, git
history, and the image — which are now three different things.

| Line | Claim | Verdict |
|---|---|---|
| 1-7 | MIT covers application code only; does not relicense the models (CC BY-NC-ND 4.0) or Essentia (AGPL-3.0) | **TRUE** — `LICENSE` (MIT) present at HEAD |
| 9-10 | Licence URIs | **TRUE** — canonical CC and GNU URLs |
| 12-14 | "Essentia is invoked as a separate subprocess at runtime; it is not linked into **or bundled with** the application." | **"linked into" TRUE; "bundled with" QUESTIONABLE — see N1** |
| 16-17 | six files "previously redistributed as tracked objects in this repository's git history and remain in that history" | **TRUE** — tracked on `origin/main`; `git rm --cached` only; no rewrite |
| 17-18 | "no longer present in the working tree" | **TRUE** — 0 tracked `.pb` at HEAD; a fresh clone has none |
| 18-19 | "as of issue #23 they are fetched at image build time from essentia.upf.edu" | **TRUE** — `Dockerfile:62` |
| 19-20 | "baked into the final Docker image (/usr/local/essentia-models/)" | **TRUE** — `Dockerfile:86` |
| 20 | "They are not committed to the working tree." | **TRUE** (phrasing is loose — one commits to a repo, not to a working tree — but the meaning is clear and correct) |
| 21-22 | "Attribution obligations … survive their removal … the bytes were distributed here" | **TRUE**, and the right thing to say |
| 27-43 | six entries, historical paths, source URLs | **TRUE** — 6/6 filenames and 6/6 URLs match the registry by derivation |
| 45-48 | ShareAlike/NoDerivatives conflict; CC BY-NC-ND 4.0 as compliance floor; application is non-commercial | **TRUE as far as I can verify** — the non-commercial characterisation is the owner's own, confirmed to you on 2026-08-14 |
| 50-51 | operators responsible for reviewing licences | disclaimer, not a factual claim |

**All three of the distinctions you asked about are now stated correctly and kept distinct**: git
history (retains the bytes), working tree (does not), image (does). That was the substance of F2 and
it is fixed.

### N1 — new observation, **inherited from #29, not introduced by #23** — LOW/MEDIUM

`NOTICE:12-14` says Essentia "is not linked into **or bundled with** the application."

`Dockerfile:26-30` installs `essentia-tensorflow==2.1b6.dev1389` into `/usr/local/essentia-venv`
**in the base stage**, which the final stage inherits. So Essentia ships inside the deployable image.

- *"not linked into"* — **accurate.** The gem shells out to a separate Python subprocess.
- *"not bundled with"* — **hard to defend.** "Bundled" is a distribution word, and the image bundles it.

This is the same shape as the F2 defect I found in round 1 — a sentence that is true of the *repo*
but false of the *image* — and it now sits four lines above a paragraph that correctly says the
models **are** baked into the image. That internal inconsistency is what makes it worth raising. It
also concerns **AGPL-3.0**, which carries the heavier distribution obligations of the two licences.

**Two reasons I am not blocking on it:** the sentence is inherited **verbatim** from `a046b69` and is
untouched by this diff (confirmed — no `+`/`-` line matching `bundled` in `a046b69..6df28b9`), and
the NOTICE hedges the paragraph as "an architectural fact … not a legal opinion." It belongs to #29.

**Suggested wording for whoever owns #29:** *"Essentia is invoked as a separate subprocess at runtime
rather than linked into the application, and is installed into the deployable image."*

---

## THE SPLIT BETWEEN #23 AND #29

**Clean at the commit level.** `6df28b9` contains only #23's own work: Dockerfile changes,
`.gitignore`/`.dockerignore` negation removal, six `.pb` deletions, the NOTICE correction, the README
update, and the two spec path fixes. `LICENSE` and the NOTICE/README *creation* come from `339796f`
and `a046b69`.

**#23 is not closable by anything omitting the build-time fetch** — confirmed present at
`Dockerfile:62`, with the final-stage verify at `:91` and zero tracked `.pb`.

**One nuance to be deliberate about:** because this branch is now *stacked on* the attribution
branch, merging it to main also lands `339796f` and `a046b69`. That is inherent to the rebase you
asked for and is correct. But it means **#29 should be closed by its own commits, not by this
branch's merge** — if the merge commit or PR references #23 only, make sure #29 is closed separately
and attributed to `339796f`/`a046b69`. That preserves the recorded decision that licence exposure
"should not be closed as a side effect of this one."

---

## WHAT I COULD NOT VERIFY

- **I did not build the image.** This machine is arm64; the image needs `linux/amd64` and
  `essentia-tensorflow`. So the implementer's amd64 cache-pair output and the "6 `.pb` in image"
  observation remain theirs, not mine. My F1 confidence rests on my own synthetic control plus the
  static ordering, both of which agree with their result.
- **I did not re-run the 298-example suite** (Litmus's remit; gates reported clean).
- **N1's legal weight** is not mine to judge — I am reporting a factual mismatch between a sentence
  and the Dockerfile, not offering a licence opinion.

---

## EVIDENCE

Read-only throughout. The merge test ran in a scratch clone **outside both repositories**:
`…/114a28aa-a39b-4f12-b984-096f60d7375d/scratchpad/vd23merge2`.

### The SHA correction

```
$ git rev-parse fix/fetch-models-at-build-time
6df28b9c464236d764674cf26182945b679be381        <- live tip, moved mid-review
$ git rev-parse .worktrees/fetch-models-at-build-time HEAD
6df28b9c464236d764674cf26182945b679be381

$ git log -1 --format='%H %ci %s' 29c94bb
29c94bb… 2026-08-14 13:48:12 -0700  Fetch Essentia models at build time; …
$ git log -1 --format='%H %ci %s' 6df28b9
6df28b9… 2026-08-14 13:53:06 -0700  Fetch Essentia models at build time; …

$ git diff --stat 29c94bb 6df28b9
 Dockerfile | 5 +++--
 1 file changed, 3 insertions(+), 2 deletions(-)

$ git merge-base --is-ancestor 6df28b9 29c94bb   -> NO
$ git rev-list --count a046b69..6df28b9          -> 1
```

The whole delta between them:

```diff
-# Verify model digests by opening each file as uid 1000, exactly as enrichment will.
-# (verify checks digests via SHA-256; readability by uid 1000 is implicitly confirmed.)
+# Verify model digests and the models directory's ownership and mode, as the runtime user.
+# (Individual model files: digest, presence, regular-file, and anti-symlink checks.
+#  Models directory: uid ownership and write-permission checks.)
```

### F1 — ordering at the live tip

```
 50	COPY vendor/* ./vendor/
 51	COPY Gemfile Gemfile.lock ./
 53	RUN bundle install && \
 56	    bundle exec bootsnap precompile -j 1 --gemfile
 58	# … This layer depends only on Gemfile.lock (copied above), so code-only deploys leave it cached. …
 62	RUN bundle exec sonance models fetch --models-dir $ESSENTIA_MODELS_DIR      <- BEFORE COPY . .
 65	COPY . .
 81	USER 1000:1000
 86	COPY --chown=rails:rails --from=build /usr/local/essentia-models /usr/local/essentia-models
 91	RUN bundle exec sonance models verify --models-dir $ESSENTIA_MODELS_DIR
```

Round-1 control, same structure, on a code-only edit with `Gemfile.lock` untouched:

```
#9 [5/7] RUN echo "=== SONANCE MODELS FETCH (network) ===" …
#9 CACHED                                                  <- stays cached before COPY . .
```

### F4 — the round-1 conflict is gone

```
$ git checkout 6df28b9 -b test-23-r2
$ git merge --no-commit --no-ff origin/fix/model-attribution-notice
Already up to date.
$ git diff --name-only --diff-filter=U
                                        <- empty: no conflicts (round 1 had NOTICE + README)

$ git checkout -B ffcheck origin/fix/model-attribution-notice
$ git merge --ff-only 6df28b9
Updating a046b69..6df28b9
Fast-forward
```

### F5 — NOTICE list derived against the registry

```
registry models: 6   NOTICE entries: 6   NOTICE urls: 6
filenames match registry? true
  in NOTICE not registry: []
  in registry not NOTICE: []
per-model URL check (NOTICE vs registry source_url):
  OK    danceability-msd-musicnn-1.pb
  OK    emomusic-msd-musicnn-2.pb
  OK    mood_acoustic-msd-musicnn-1.pb
  OK    mood_happy-msd-musicnn-1.pb
  OK    mood_relaxed-msd-musicnn-1.pb
  OK    msd-musicnn-1.pb
```

### F3 + core requirements at the live tip

```
$ git grep -n "tmp/essentia_models" 6df28b9 -- '*.rb' '*.rake'
6df28b9:spec/fixtures/sonance/generate_goldens.rb:9:  … ENV.fetch("ESSENTIA_MODELS_DIR", root.join("tmp/essentia_models").to_s)
6df28b9:spec/integration/essentia_extract_golden_spec.rb:19:  … ENV.fetch("ESSENTIA_MODELS_DIR", ROOT.join("tmp/essentia_models").to_s)
   ^ both are fallbacks inside ENV.fetch, which is correct

tracked .pb:                0
build-time fetch present:   1
final-stage verify present: 1
```

### N1 — Essentia is installed into the image

```
 26	RUN apt-get update -qq && \
 27	    apt-get install --no-install-recommends -y python3 python3-venv ffmpeg && \
 28	    python3 -m venv /usr/local/essentia-venv && \
 29	    /usr/local/essentia-venv/bin/pip install --no-cache-dir "essentia-tensorflow==2.1b6.dev1389" "yt-dlp" && \

$ git diff a046b69 6df28b9 -- NOTICE | grep -E "^[+-].*bundled"
  (no output — sentence inherited verbatim from a046b69, untouched by #23)
```

### Repo state

Read-only. No edits, no commits, no staging, nothing pushed. The merge test ran in a scratch clone
outside both repositories. Both repos remain on their original branches.

---

## SUMMARY

**APPROVE at `6df28b9`.** Closed: **F1, F2, F3, F4, F5, F6** — all six.

Carried forward, not blocking this branch:

- **N1** — `NOTICE:12-14` "not … bundled with the application" versus Essentia being installed into
  the image at `Dockerfile:26-30`. Inherited verbatim from `a046b69`; route to **#29**.
- **Confirm the HEAD.** My APPROVE is for `6df28b9`. On `29c94bb` — the SHA your dispatch named —
  F6 would remain open and the verdict would be REQUEST-CHANGES.
- **Close #29 on its own commits**, not as a side effect of merging this stacked branch.
