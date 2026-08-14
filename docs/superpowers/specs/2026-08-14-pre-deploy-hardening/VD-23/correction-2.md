## Second correction: my first correction was also wrong. The models are already in the image.

I have now been wrong about this issue twice, in opposite directions. Recording the verified
chain so the next reader does not have to re-derive it.

| Claim | Status |
|---|---|
| Original filing: ~3.6 MB re-downloaded every deploy; container needs egress to essentia.upf.edu | **False** |
| First correction: `/rails/tmp/essentia_models` is empty in every container; enrichment fails with `ConfigurationError` | **Also false** |
| Actual: the six model files are tracked in git and land in the production image via `COPY . .` | **Verified** |

### The chain, verified line by line

The six `.pb` files are **tracked in git**:

```
$ git ls-tree -r -l origin/main | grep '\.pb$'
100644 blob 0bfd38d…    82458  tmp/essentia_models/danceability-msd-musicnn-1.pb
100644 blob 6de146e…    82460  tmp/essentia_models/emomusic-msd-musicnn-2.pb
100644 blob e3d6d8c…    82458  tmp/essentia_models/mood_acoustic-msd-musicnn-1.pb
100644 blob de9af07…    82458  tmp/essentia_models/mood_happy-msd-musicnn-1.pb
100644 blob 92d7dfd…    82458  tmp/essentia_models/mood_relaxed-msd-musicnn-1.pb
100644 blob f3466c8…  3197999  tmp/essentia_models/msd-musicnn-1.pb
```

They survive the `tmp/` exclusions because both ignore files exclude and then **re-include**:

- `.gitignore:16` `/tmp/*`, then `:33` `!/tmp/essentia_models/` and `:34` `!/tmp/essentia_models/*.pb`
- `.dockerignore:19` `/tmp/*`, then `:34-35` the **identical** two negations

So they enter the build context, land via `Dockerfile:58 COPY . .`, and reach the final image via
`Dockerfile:80 COPY --chown=rails:rails --from=build /rails /rails`, owned by uid 1000, matching
`USER 1000:1000` at `Dockerfile:76`.

All six SHA-256 digests match `Registry.default` exactly, 6 of 6. The Principal ran
`ModelStore#verify!` against the real app path: **VERIFIED OK 6/6**.

Everything else in my first correction held and the design builds on it: nothing downloads at
runtime, `verify!` only compares digests, `fetch!` is CLI-only, all `.kamal/hooks` are `.sample`,
and `ConfigurationError` is an unrescued `FatalError`. Only the where-do-the-bytes-come-from link
was wrong — and it inverts the remedy.

**Enrichment is not broken for missing models, and the container has never needed egress.**

### What is actually wrong — narrower, but real

1. **Licence exposure.** This repository is **public**, and it redistributes six
   CC-BY-NC-ND-4.0 model binaries with **no LICENSE and no NOTICE at root**. Filed separately as
   a distinct issue, because it is a compliance matter with different urgency from deploy
   mechanics and should not be closed as a side effect of this one.
2. **Production-critical assets live in `tmp/`** — the one directory every convention treats as
   disposable — protected only by four negation lines that nothing tests.
3. **Nothing in the build would notice if they vanished.** Build green, deploy green, first
   enrichment fails.

### Accepted design

Remove the binaries from git; fetch at **build time** in the Dockerfile via the gem CLI into
`/usr/local/essentia-models`; run `sonance models verify` in the **final** stage as uid 1000, so
it validates digests *and* ownership *and* mode exactly as the runtime user sees them. No volume,
no deploy hook, no gem change.

A volume was never viable — an empty persistent volume is still empty and nothing writes to it.
A deploy hook fails later than a build step; build time is the earliest possible failure point.

**Trade accepted:** image builds gain a hard dependency on `essentia.upf.edu`, an academic host
with no SLA. Bounded, because previously built images still deploy and roll back, and the fetch
layer caches on `Gemfile.lock`, so code-only deploys never refetch. Image growth is 3.44 MiB,
about 0.7% of the essentia package the image already carries (484 MiB measured).

Git history retains the blobs. A history rewrite is **not** recommended for 3.44 MiB.

On the standing "do not vendor model binaries into git" constraint: it is already violated by the
status quo. This plan does not add a violation, it ends one. Had the repo been clean, that
constraint would have ruled this option out; instead it rules out keeping things as they are.

### `ConfigurationError` — surface it, do not rescue

The taxonomy already encodes the distinction: `TrackError` means *this track*, `FatalError` means
*this run*. A missing model is identical for every album.

Rescuing would convert a one-line infrastructure fix into a silent per-album `llm_only`
downgrade — **and that has already happened here.** `enrichment.rake:14-16` exists to reground
albums because production once ran without a working essentia toolchain. `ApplicationJob` sets no
`retry_on`, so it fails once into failed executions rather than looping.

The legitimate complaint is about *when*, not *whether*. Keep it fatal; make it unreachable by
failing the build instead.

### The proof an implementer will get wrong

The obvious check **does not discriminate**. The old configuration *passes* models-verify under
`--network none`, because the models really are there.

The real negative control is applying the **same sabotage to both** — delete the `.dockerignore`
negations:

- **OLD**: build exits 0, produces a broken image, fails only at first enrichment.
- **NEW**: build exits **non-zero**, no image is produced.

Also proven live: corrupting one byte gives `model digest mismatch`; mode 0775 gives a
group-or-world-writable rejection; an empty directory gives `missing model`. Note the two
messages differ — missing model reports the **full path**, digest mismatch reports the
**basename**. This issue's original text cites the digest message for what is actually the
missing-file case.

### One unconfirmed fact the plan rests on

Whether the remote builder `5.78.177.23` has egress to `essentia.upf.edu`. **Not yet verified.**

If it does **not**, the fallback is *not* reverting to the status quo: move the bytes to
`vendor/essentia_models/` — out of `tmp/` — add the NOTICE, and keep the verify gate.

### Risk triggers

New dependency (build-time, genuinely new) — **yes**. External automation config, Dockerfile and
deploy.yml — **yes**. Destructive operation, `git rm --cached` of six tracked binaries — **yes**.
Runtime external integration — **explicitly no**, unchanged and proven under `--network none` on
both configurations. No migration, no authz, no data-exposure change. Every security control is
untouched; the plan adds a verification point and removes none.

### Attribution

Third premise correction on this issue. Found by the Principal, who declined to build on my
corrected premise without checking it. Every line cited above was re-verified independently by
the Team Manager.
