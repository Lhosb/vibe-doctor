# vibe-doctor #23 — how the Essentia model bytes reach production

**Author:** Keystone (Principal Engineer) · **Date:** 2026-08-14 · **Tier 1, plan only**
**Base:** `Lhosb/vibe-doctor` `origin/main` = `5c9dfcc` (local `main` 4 commits behind, fetched first)
**Gem:** pinned at tag `v0.3.0`

---

## ⚠️ THIRD PREMISE CORRECTION — the models are already in the image

I was asked not to re-litigate the corrected premises. I have to correct one of them anyway, because
a design built on it would propose work that is already done.

> **The corrected premise says: "`/rails/tmp/essentia_models` is empty in every deployed container and
> nothing populates it." That is false. `COPY . .` populates it, deliberately, and all six files
> verify against the gem's pinned digests.**

Everything else in the correction holds and I build on it: nothing downloads at runtime, `verify!`
only compares digests, `fetch!`'s sole caller is the CLI, no hook is active, and `ConfigurationError`
is an unrescued `FatalError`. Those are all confirmed below. The single wrong link is *where the bytes
come from* — and it inverts the remedy.

**The mechanism, every link verified:**

| Step | Evidence |
|---|---|
| The six `.pb` files are **tracked in git** | `git ls-tree -r 5c9dfcc -- tmp/essentia_models` → 6 blobs, 82458–3197999 bytes |
| Tracked **deliberately** — `.gitignore` excludes `/tmp/*` then re-includes them | `.gitignore:16` `/tmp/*`; `.gitignore:33-34` `!/tmp/essentia_models/`, `!/tmp/essentia_models/*.pb` |
| Included in the **Docker build context** deliberately, by the same double negation | `.dockerignore:19` `/tmp/*`; `.dockerignore:34-35` `!/tmp/essentia_models/`, `!/tmp/essentia_models/*.pb` |
| `COPY . .` puts them in the build stage | `Dockerfile:58` |
| Final stage copies them in, **owned by uid 1000** | `Dockerfile:80` `COPY --chown=rails:rails --from=build /rails /rails` |
| Container runs as that uid, satisfying ModelStore's owner check | `Dockerfile:76` `USER 1000:1000` |
| Landing path is exactly the configured default | `Rails.root/tmp/essentia_models` = `/rails/tmp/essentia_models` |
| **All six match the gem's pinned SHA-256** | 6/6 identical, table in §4 |
| `verify!` passes against the real app directory | `ModelStore#verify! → VERIFIED OK (6/6)` |

So audio grounding is **not** broken in production for want of model files. Issue #23's revised
severity ("it is not wasteful, it is broken") is also wrong, in the opposite direction from the
original filing.

**What is actually wrong** is narrower, and real:

1. **The repo is PUBLIC and redistributes six CC-BY-NC-ND-4.0 binaries with no LICENSE, no NOTICE and
   no attribution at its root.** `gh repo view` → `"visibility":"PUBLIC"`. A root-level licence/notice
   grep matches only `.gitattributes`. The gem ships both a `NOTICE` and per-model attribution
   printed by its CLI precisely because these files carry attribution obligations; the app inherited
   the binaries and none of the obligations.
2. **The provisioning mechanism is invisible.** It is two negation lines in each of two ignore files,
   placing production-critical assets under `tmp/` — the one directory every convention in Rails,
   Docker and git treats as disposable. A routine "clean up tmp/" would silently ship a broken image.
3. **Absence is not gated anywhere in the build.** If those files vanished, the build would succeed,
   the deploy would succeed, and the first enrichment would fail — which is exactly the failure shape
   the issue wants eliminated, just from a different cause than it identified.

That reframes the question from *"how do the bytes get in"* (they already do) to *"is git the right
place for them, and what makes their absence loud?"*

---

## 1. VERIFIED FACTS

Everything below was read at `5c9dfcc` or executed. Unconfirmed items are marked.

### Call sites and default path

| Fact | Location |
|---|---|
| `models_dir` defaults to `Rails.root.join("tmp", "essentia_models")`, four call sites | `app/jobs/enrich_album_job.rb:6`, `app/services/mood_grounding_service.rb:11`, `lib/tasks/enrichment.rake:19`, `lib/tasks/enrichment.rake:32` |
| `ESSENTIA_MODELS_DIR` is read at all four, set nowhere in deploy config | `git grep ESSENTIA_MODELS_DIR 5c9dfcc -- app lib config` → those four lines only |
| It is documented only as an "optional variable" | `README.md:65-70` |

### Deploy configuration

| Fact | Location |
|---|---|
| One volume, `vibe_doctor_storage:/rails/storage` | `config/deploy.yml:78-79` |
| `env.clear` sets `RAILS_ENV`, `RAILS_LOG_TO_STDOUT`, `SOLID_QUEUE_IN_PUMA`, `DB_HOST` — **no** `ESSENTIA_MODELS_DIR` | `config/deploy.yml:48-66` |
| Builder is remote, on the production host, amd64 | `config/deploy.yml:87-89` (`arch: amd64`, `remote: ssh://deploy@5.78.177.23`) |
| Every `.kamal/hooks` entry is `.sample`, therefore inactive | `git ls-tree -r 5c9dfcc -- .kamal/hooks` → 9 files, all `.sample` |
| `deploy.yml` and `Dockerfile` unchanged between `b26cf31` and `5c9dfcc` | `git diff --stat` empty |

### Image build

| Fact | Location |
|---|---|
| `essentia-tensorflow==2.1b6.dev1389` + `yt-dlp` installed into a venv at build | `Dockerfile:26-31` |
| No model fetch or bake step in the Dockerfile | confirmed by reading all 87 lines |
| Gems installed from `Gemfile.lock` **before** `COPY . .`, so a fetch step could cache on the lock | `Dockerfile:49-55` then `:58` |
| Final stage runs as uid/gid 1000 | `Dockerfile:76` |
| Entrypoint runs `db:prepare` + `db:seed` for the server command only; no model handling | `bin/docker-entrypoint:1-9` |
| The gem exposes its CLI, so `bundle exec sonance` is available at build | `sonance.gemspec:23-24` (`bindir = "exe"`, `executables = ["sonance"]`) |

### Gem behaviour (v0.3.0, runtime code identical to gem `main`)

| Fact | Location |
|---|---|
| `Extractor#verify!` → `ModelStore#verify!` | `lib/sonance/extractor.rb:40`, `lib/sonance/model_store.rb:198-201` |
| `verify_model!` compares **SHA-256 only** and raises `ConfigurationError: model digest mismatch: <basename>` | `model_store.rb:218-222` |
| A **missing** file raises `ConfigurationError: missing model: <full path>` — a *different* message from the digest-mismatch case | `model_store.rb:53-54`; verified by execution |
| `fetch!` is the only download path; only caller is the CLI | `model_store.rb:203-207`, `exe/sonance:61` |
| `ConfigurationError < FatalError`, a **sibling** of `TrackError` | `lib/sonance/errors.rb:23` vs `:8` |
| Models dir must be owned by `Process.euid` and must not be group/world-writable | `model_store.rb:144-153`; verified by execution (mode `0775` rejected, `0700` accepted) |
| Download host allowlist is HTTPS-only, single host, **re-validated on every redirect hop** | `model_store.rb:10`, `:12-20`, `:178-189` |
| Six models, **3,610,291 bytes total (3.44 MiB)** | derived from `Registry.default` |

**Precision on the non-negotiable:** `byte_length` is **declared metadata and is not compared against
the file** at either fetch or verify — only SHA-256 is. `Model`'s initializer validates that
`byte_length` is a positive Integer (`registry.rb:50-57`), nothing more. This is not a defect: a file
matching a SHA-256 necessarily has the declared length, so the property survives cryptographically. I
note it because "keep byte_length verification meaningful" cannot mean "preserve a comparison" — there
is none to preserve. Preserving the digest check preserves both.

### App error handling

| Fact | Location |
|---|---|
| `MoodGroundingService` rescues `Sonance::TrackError` and `Faraday::Error` only | `mood_grounding_service.rb:116`, `:119`, `:129` |
| `ConfigurationError` is therefore **unrescued** and fails the job | follows from `errors.rb:23` |
| `ApplicationJob` configures **no** `retry_on` / `discard_on` (both commented out) | `app/jobs/application_job.rb:1-7` |
| An existing spec already gates "empty dir raises, gem does not self-populate" | `spec/integration/essentia_empty_models_spec.rb:19-28` |
| Boot-time initializer already asserts mapped descriptors exist and emomusic native ranges match | `config/initializers/sonance_registry.rb` |

**Consequence of no retry config:** a fatal misconfiguration fails each job **once** into Solid Queue's
failed executions rather than retrying forever. That is the right posture and needs no change.

### Marked unconfirmed

- **Whether the remote builder host `5.78.177.23` has outbound HTTPS egress to `essentia.upf.edu`.** I
  cannot test this from here. It is load-bearing for the decision in §2 and is the implementer's first
  task in §3, step 0.
- Whether `spin-doctor.lolabs.dev` constitutes commercial use under CC-BY-NC-ND-4.0's NonCommercial
  term. Out of my scope; flagged for the owner. The attribution gap in §0 is factual regardless.
- Actual built image size. I measured the local `essentia` package at **484 MiB** as a proxy for the
  cost the image already pays; the 3.44 MiB of models is ~0.7% of that one dependency.

---

## 2. THE DECISION

### 2a. Provisioning: remove the binaries from git; fetch them at image build time

**Chosen: delete `tmp/essentia_models` from version control and both ignore-file negations, and add a
build-time `sonance models fetch` to the Dockerfile, landing at `/usr/local/essentia-models`, followed
by a `sonance models verify` in the final stage that fails the build if anything is wrong.**

No volume. No deploy hook. No gem change.

**Why not keep the status quo,** which does technically work? Three reasons, and the first is not
about engineering:

1. **A public repo redistributes CC-BY-NC-ND-4.0 binaries with no attribution.** The gem carries a
   `NOTICE`, a `LICENSE.txt`, and prints per-model attribution from its CLI. The app carries none of
   that and publishes the artifacts anyway. Removing them from the repo resolves this at HEAD.
2. **The brief forbids vendoring model binaries into git.** The status quo already violates that
   constraint; I am not choosing to add a violation, I am choosing to end one. Had I found the repo
   clean, "do not vendor" would have ruled out this option — instead it rules out *keeping* it.
3. **`tmp/` is the worst possible home for a production-critical asset.** Every convention in the
   stack treats it as disposable, and the only thing preventing that is two negation lines in each of
   two ignore files that nothing tests.

**Why not a volume?** A volume cannot fix this and never could: an empty persistent volume is still
empty, and nothing in the app writes to it. It would add a mutable, persistent, writable location for
files the gem's own security note asks to keep un-writable — strictly worse than an immutable image
layer, for no benefit.

**Why not a deploy hook running the CLI fetch?** It moves the failure later, not earlier. A hook fails
*during* deploy, after the image is built and possibly after traffic has shifted; a build step fails
*before* anything is deployed. Build-time is the earliest point at which this can fail, and earliest
is best. It also keeps every deployed image self-describing: the models are a layer, not an
environmental side effect.

**What I give up, plainly:**

- **Image builds gain a hard dependency on `essentia.upf.edu`.** If that host is down or reorganises
  its URLs, **you cannot build a new image.** This is a real availability coupling to an academic host
  with no SLA, and it is the genuine cost of this choice. Two things bound it: a previously built
  image can always be redeployed (Kamal deploys an image, and rollback does not rebuild), and the
  fetch layer caches on `Gemfile.lock`, so routine code-only deploys never re-fetch.
- **~3.44 MiB added to the image.** Against a base that already installs `essentia-tensorflow`
  (~484 MiB locally measured) plus `yt-dlp`, `ffmpeg` and `libvips`, this is ~0.7% of one dependency.
  I consider the size objection closed.
- **Git history still contains the blobs.** Removing them from HEAD does not purge history. I am
  **not** recommending a history rewrite — it would break every existing clone and every commit SHA
  for a 3.44 MiB artifact. If the licensing exposure needs to be fully closed, that is an owner
  decision with a much larger blast radius, and it belongs in its own issue.

**One unconfirmed fact this rests on, and the contingency.** I could not verify that the remote
builder (`5.78.177.23`, `config/deploy.yml:89`) has outbound HTTPS to `essentia.upf.edu`. §3 step 0
verifies it in one command. **If it does not, do not fall back to the status quo** — instead keep the
bytes in the repo but move them to `vendor/essentia_models/` (out of `tmp/`, into a directory the
Dockerfile already treats as real at `Dockerfile:49`), add the `NOTICE` from §5, and keep the
final-stage verify gate from §3. That fallback fixes the invisibility and the attribution while
leaving the vendoring question open for the owner. Everything else in this plan is unchanged either
way.

### 2b. Should `ConfigurationError` be rescued or surfaced?

**Surfaced. Do not rescue it. It is correct as it stands — but it is firing in the wrong place, and
§3 moves the detection earlier rather than softening the error.**

The gem's taxonomy already encodes the distinction that matters: `TrackError` means *this track is
unusable*, `FatalError` means *this run is unusable* (`lib/sonance/errors.rb:8` vs `:23`). They are
siblings precisely so a consumer can treat them differently, and `MoodGroundingService` correctly
rescues only the former (`:116`, `:129`).

A missing or corrupt model is not a property of one album. It is identical for every album and will
remain so until someone fixes the deployment. Rescuing it would convert a systematic, one-line-to-fix
infrastructure fault into a silent per-album downgrade to the `llm_only` fallback — every album
"succeeding" with materially worse data and no signal anywhere. **That failure has already happened
on this project**: `lib/tasks/enrichment.rake:14-16` exists to re-ground albums because "production
ran without a working essentia toolchain, so none of them ever got real audio analysis." Rescuing
`ConfigurationError` is the mechanism that would let that recur, quietly.

Two supporting facts confirm the current posture is safe:

- `ApplicationJob` sets no `retry_on` (`app/jobs/application_job.rb:1-7`), so a fatal misconfiguration
  fails once into Solid Queue's failed executions rather than retrying forever.
- The behaviour is already gated: `spec/integration/essentia_empty_models_spec.rb:19-28` asserts an
  empty models directory raises `ConfigurationError` and that the gem does **not** self-populate.

**The real complaint behind the question — "it kills the job" — is a complaint about *when*, not
*whether*.** The answer is not to catch it later but to make it impossible to reach a job: the
final-stage `models verify` in §3 fails the **build**, so a bad image is never produced, never pushed,
and never deployed. Keep the error fatal; ensure it never gets the chance to fire.

---

## 3. IMPLEMENTATION PLAN

### Step 0 — verify the one unconfirmed fact (do this first)

```sh
ssh deploy@5.78.177.23 'curl -sSI --max-time 10 \
  https://essentia.upf.edu/models/feature-extractors/musicnn/msd-musicnn-1.pb | head -1'
```

Expect `HTTP/… 200`. If this fails, switch to the `vendor/essentia_models/` fallback in §2a and skip
steps 2 and 3 below (keep steps 4–7).

### Step 1 — `.gitignore`: delete the negations

Remove lines 33–34:

```
!/tmp/essentia_models/
!/tmp/essentia_models/*.pb
```

### Step 2 — `.dockerignore`: delete the negations

Remove lines 34–35 (identical two lines). After this, `/tmp/*` at line 19 excludes them again.

### Step 3 — untrack the binaries

```sh
git rm -r --cached tmp/essentia_models
```

Files stay on disk for local development; they leave the index. Local `rspec` keeps working because
`spec/integration/essentia_extract_golden_spec.rb:19` still points at `tmp/essentia_models`. Do **not**
rewrite history (§2a).

### Step 4 — `Dockerfile`: fetch at build, verify in the final stage

**4a.** In the **base** stage, immediately after the existing `ENV` block ending at line 38, add one
line so both later stages inherit the path:

```dockerfile
ENV ESSENTIA_MODELS_DIR="/usr/local/essentia-models"
```

**4b.** In the **build** stage, after the `bundle install` block ending at line 55 and **before**
`COPY . .` at line 58, add:

```dockerfile
# Fetch the pinned Essentia model files at build time so the runtime image needs no outbound
# network. Sonance verifies each file against its registry-pinned SHA-256 and installs nothing
# on mismatch. Requires BUILD-TIME egress to essentia.upf.edu -- see README "Deployment".
RUN bundle exec sonance --models-dir "$ESSENTIA_MODELS_DIR" models fetch
```

Placing it here is deliberate: the layer's cache key is `vendor/`, `Gemfile` and `Gemfile.lock`
(`Dockerfile:49-50`). The pinned digests live in the gem, and the gem is pinned by `Gemfile.lock`, so
the cache invalidates **exactly** when the models could change and never merely because app code did.

**4c.** In the **final** stage, after line 80 (`COPY … --from=build /rails /rails`), add:

```dockerfile
COPY --chown=rails:rails --from=build /usr/local/essentia-models /usr/local/essentia-models

# Build-time gate: fails the build if any model is missing, digest-mismatched, or has ownership
# or permissions the runtime user cannot accept. Runs as uid 1000, the runtime identity.
RUN bundle exec sonance --models-dir "$ESSENTIA_MODELS_DIR" models verify
```

The `--chown` is load-bearing, not cosmetic: `ModelStore` refuses a models root not owned by the
current euid (`model_store.rb:144-148`), and the final stage runs as `USER 1000:1000`
(`Dockerfile:76`). Because the `RUN` sits after `USER`, it executes as uid 1000 and therefore
validates the exact ownership and mode the running app will see. `/usr/local/essentia-models` is
outside `/rails`, so `COPY . .` cannot clobber it, and it sits beside the existing
`/usr/local/essentia-venv`.

### Step 5 — `config/deploy.yml`: declare the path

Under `env.clear` (currently lines 48–66), after `DB_HOST` at line 63:

```yaml
    # Essentia model files are baked into the image at /usr/local/essentia-models by the
    # Dockerfile. Stated here so the path is visible in deploy config; must match the
    # Dockerfile ENV. spec/deploy_config_spec.rb asserts the two agree.
    ESSENTIA_MODELS_DIR: /usr/local/essentia-models
```

No `volumes:` change. Do not add a volume.

### Step 6 — the drift gate

The value now appears in two files, so assert they agree. New spec, e.g.
`spec/deploy_config_spec.rb`: parse `config/deploy.yml`, read `env.clear.ESSENTIA_MODELS_DIR`, grep
the `ENV ESSENTIA_MODELS_DIR` line out of `Dockerfile`, assert equal. Without this the duplication is
a latent drift bug rather than useful redundancy.

### Step 7 — documentation and attribution (detailed in §5)

`README.md` under `## Deployment`, plus a new root `NOTICE`.

### Not changed

The four `models_dir` call sites keep their `Rails.root.join("tmp", "essentia_models")` fallback —
that remains the correct local-development default, and `ESSENTIA_MODELS_DIR` overrides it in the
image. No app code changes. No gem changes.

---

## 4. HOW IT IS PROVEN

The check that matters is: **a freshly built image contains valid, digest-verified models at
`ESSENTIA_MODELS_DIR`, and the build fails loudly if it does not.**

That is two properties, and they discriminate differently. I state that plainly, because claiming a
control discriminates when it does not is the same error as shipping a gate that cannot fail.

| Check | Old config | New config | Discriminates? |
|---|---|---|---|
| **A** — image contains valid models; no runtime egress needed | **PASSES** | PASSES | **No.** Report this honestly. |
| **B** — absence is caught at *build* time | **FAILS** | PASSES | **Yes** — the real control |
| **C** — repo contains no model binaries | **FAILS** | PASSES | Yes |

### Check A — must be run, must be reported as non-discriminating

The old configuration already ships working models. An implementer who runs only this check will
"prove" the fix works and will have proved nothing.

```sh
docker build --platform linux/amd64 -t vd-models .
docker run --rm --network none --entrypoint bash vd-models \
  -c 'bundle exec sonance --models-dir "$ESSENTIA_MODELS_DIR" models verify'
```

Expect `Models verified`, exit 0, **on both the old and the new Dockerfile** (with
`ESSENTIA_MODELS_DIR=/rails/tmp/essentia_models` for the old). `--network none` is the meaningful part:
it proves the runtime needs no egress, which was true before this change and stays true after.

### Check B — the negative control (the one that earns its place)

Apply the **same sabotage** to both configurations and observe that only the new one catches it.

*Sabotage:* delete the two `!/tmp/essentia_models/…` lines from `.dockerignore` (old) — i.e. simulate
the routine "tidy up tmp/" that the current design cannot survive.

```sh
# OLD config + sabotage
docker build --platform linux/amd64 -t vd-old-sabotaged .     ; echo "build exit: $?"
docker run --rm --network none --entrypoint bash vd-old-sabotaged \
  -c 'bundle exec sonance --models-dir /rails/tmp/essentia_models models verify' ; echo "verify exit: $?"
```

**Required outcome — build exit 0, verify exit 1** with
`missing model: /rails/tmp/essentia_models/msd-musicnn-1.pb`. That is the defect: **the build
succeeded and shipped a broken image.**

```sh
# NEW config + equivalent sabotage (make the fetch produce nothing, e.g. break the fetch step)
docker build --platform linux/amd64 -t vd-new-sabotaged .     ; echo "build exit: $?"
```

**Required outcome — build exit non-zero**, failing at the final-stage
`RUN bundle exec sonance … models verify` with the same `missing model:` message. **No image is
produced.** If this build succeeds, the gate is vacuous and the change has not worked.

### Check C — repo cleanliness, with a floor

```sh
git ls-files tmp/essentia_models | wc -l     # expect 0 after; 6 before
git -C . grep -c "essentia_models" -- .dockerignore .gitignore   # expect 0 after; 2 each before
```

Assert the **before** value too. A "0 files tracked" assertion passes vacuously if the path is
mistyped; asserting that it was 6 beforehand proves the check is looking at the right place.

### Gem-level controls already executed (reusable as-is)

These I ran during this review; they establish that the digest gate is live and can fail.

**All six tracked blobs match the pinned digests — 6/6:**

```
danceability-msd-musicnn-1.pb   874a4b86afc9e12de3f15a47baf9ff1ac676ace109c56203e26103f2259eb95e
emomusic-msd-musicnn-2.pb       fcfb486510213b35e0a691975325f58170f648ad4a02d749bce790da13ded43b
mood_acoustic-msd-musicnn-1.pb  519ee3af8210fe32e021002a0094546aeb6fb5a59d22b7d53c48e4ee1ac9e6cc
mood_happy-msd-musicnn-1.pb     d7382bc60304ea4578c298222968cd8d600c31252c7bf3e90b1f728ebb3ec36d
mood_relaxed-msd-musicnn-1.pb   1252d28ca7d2204e34e0cdf84a00aa2bc9627a87bdcf923df3aad39cfa69d2d9
msd-musicnn-1.pb                cdea0722bcee7f731286843f2233e3aa69887bb5c3e2dce011eff55f38d04f3e
```
Identical to `Registry.default`'s pinned values, byte counts included.

**The digest gate fails when it should** (append one byte, then verify):
```
CORRUPTED byte appended -> ConfigurationError: model digest mismatch: mood_happy-msd-musicnn-1.pb
```

**The permission gate fails when it should:**
```
POPULATED, mode 0700 (control)       -> VERIFIED OK
POPULATED, mode 0775 group-writable  -> ConfigurationError: models directory misconfiguration:
                                        must not be group- or world-writable
EMPTY dir                            -> ConfigurationError: missing model: …/msd-musicnn-1.pb
```

**The real app path verifies:**
```
ModelStore#verify! against vibe-doctor/tmp/essentia_models -> VERIFIED OK (6/6)
```

Note the two distinct failure messages — `missing model: <full path>` versus `model digest mismatch:
<basename>`. Any spec asserting on these must match the right one; the issue text cites the
digest-mismatch message for what is actually the missing-file case.

---

## 5. WHERE THE `essentia.upf.edu` DEPENDENCY GETS RECORDED

Four places, each for a different reader. The first two are the ones that stop this being
rediscovered by the next audit.

**1. `README.md`, under `## Deployment` (line 142)** — the canonical home. Add:

```markdown
### Build-time external dependencies

The image build fetches artifacts from two external hosts. **Neither is contacted at runtime** —
a deployed container needs no outbound access for enrichment.

| Host | What | When | If unreachable |
|---|---|---|---|
| `essentia.upf.edu` | Six Essentia model files (3.44 MiB), fetched by `sonance models fetch` | Image build; layer caches on `Gemfile.lock` | **Build fails.** Previously built images still deploy and roll back normally. |
| `pypi.org` | `essentia-tensorflow`, `yt-dlp` (`Dockerfile:26-31`) | Image build | Build fails. |

Models are verified against SHA-256 digests pinned in the `sonance` registry, at fetch and again in
the final image stage. A mismatch fails the build.
```

The `pypi.org` row is not scope creep: it is the same class of undeclared build-time dependency, it
already exists, and recording one while omitting the other guarantees the next audit re-files it.

**2. `Dockerfile`, inline at the fetch step** — §3 step 4b. The reader who breaks it is reading the
Dockerfile, not the README.

**3. `config/deploy.yml`, inline comment on `ESSENTIA_MODELS_DIR`** — §3 step 5. The operator
wondering where models live looks here first.

**4. A new root `NOTICE`** — this is the licensing obligation from §0, not documentation:

```
This product includes Essentia machine-learning models developed by the
Music Technology Group, Universitat Pompeu Fabra.

  Source:      https://essentia.upf.edu/models/
  Licence:     CC-BY-NC-ND-4.0
  Attribution: Music Technology Group, Universitat Pompeu Fabra
  Use:         non-commercial only

The model files are not distributed in this repository. They are fetched at image
build time and verified against SHA-256 digests pinned in the sonance gem registry.
```

The gem already ships exactly this content in its own `NOTICE` and prints it from
`exe/sonance` at fetch; the app should mirror it. **If the owner chooses the
`vendor/essentia_models/` fallback from §2a, this file is mandatory rather than
advisable** — the repo would still be publicly redistributing the binaries.

---

## 6. RISK TRIGGERS

Using this project's established trigger vocabulary (migration / authz / data exposure / destructive
op / runtime external integration / new dependency / external automation config):

| Trigger | Touched | Detail |
|---|---|---|
| **New dependency** | **YES** | A **build-time** external integration with `essentia.upf.edu` is genuinely new. The bytes previously came from git; now they come from the network. This is the single largest risk the change introduces and §2a states its cost. |
| **External automation config** | **YES** | `Dockerfile` (build) and `config/deploy.yml` (deploy) both change. |
| **Destructive op** | **YES** | `git rm -r --cached tmp/essentia_models` untracks six binaries, and four ignore-file lines are deleted. Reversible from history, but it is deletion of tracked content and should be reviewed as such. |
| **Runtime external integration** | **NO** | Explicitly unchanged. The runtime needed no egress before and needs none after — Check A proves it under `--network none` on both configurations. |
| **Migration** | NO | No schema or data change. |
| **Authz change** | NO | None. |
| **Data exposure** | NO — but adjacent | No user or application data is exposed. The *licensing* exposure in §0 (public redistribution of CC-BY-NC-ND binaries without attribution) is a real compliance matter that this change closes at HEAD; it is not a data-exposure trigger, and I flag it separately so it is not filed under the wrong heading. |

**Tier 1 is correct and is not generous here.** The change touches the build and deploy path for a
production service, introduces a new external dependency in that path, and deletes tracked content.
It also rests on one unconfirmed fact (§3 step 0) whose falsity redirects the whole plan.

**Security controls: unchanged.** The `DOWNLOAD_HOST` allowlist, its per-redirect-hop re-validation
(`model_store.rb:178-189`), the HTTPS-only requirement, the `.pb`-basename regex, `NOFOLLOW`/symlink
handling, and the SHA-256 verification are all untouched. This plan **adds** a verification point (the
final-stage `models verify`, run as the runtime uid) and removes none. No gem change is required. If
upstream availability later forces an internal mirror, that would need a `DOWNLOAD_HOST` change — a
**gem** change, belonging in a new `Lhosb/sonance` issue, and explicitly out of scope here.

---

## Summary

The models are already in the production image, placed there deliberately by two negation lines in
`.gitignore` and `.dockerignore` and carried in by `COPY . .`. All six verify against the gem's pinned
digests. Enrichment is not broken for want of model files, and the container has never needed egress.

What is wrong is that production-critical binaries live in `tmp/` behind an invisible mechanism, that
a public repository redistributes CC-BY-NC-ND artifacts with no attribution, and that nothing in the
build would notice if the files disappeared.

The fix is to stop shipping them in git, fetch them at build time with the gem's own CLI, and gate the
final image with a `models verify` that runs as the runtime user — turning a silent runtime failure
into a loud build failure. `ConfigurationError` stays fatal and unrescued; the change makes it
unreachable rather than making it quieter.

The whole plan rests on one unverified fact — whether the remote builder can reach
`essentia.upf.edu` — and §3 step 0 settles it in one command, with a named fallback if it cannot.
