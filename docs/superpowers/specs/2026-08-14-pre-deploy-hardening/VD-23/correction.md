## Correction: this issue's stated mechanism was wrong. The defect is real and more severe.

I filed this issue claiming the models are **re-downloaded every deploy** and that the running
container therefore **needs outbound HTTPS to essentia.upf.edu**. Both claims are wrong. A
premise check by the Principal prompted me to re-derive it from the code, and here is what is
actually true.

### The app never downloads models at runtime

- `Sonance::Extractor#verify!` (`lib/sonance/extractor.rb:40`) calls `model_store.verify!`.
- `ModelStore#verify!` (`lib/sonance/model_store.rb:198-201`) only compares digests. It has no
  download path.
- `ModelStore#fetch!` (`lib/sonance/model_store.rb:203`) is the **only** downloading path, and
  its sole caller in either repo is the CLI at `exe/sonance:61`.
- `git grep` across `app/ lib/ config/` in vibe-doctor finds no call to `fetch!` and no other
  model provisioning. All `.kamal/hooks/*` are still `.sample` and inactive.

This is deliberate gem design, not an oversight. The Phase A plan states it outright at
`docs/superpowers/plans/2026-08-07-essentia-ruby-gem-extraction.md:407`:

> `#fetch!` downloads on explicit instruction only, never implicitly at analyze time

So the gem is correct. The gap is entirely on the app/deploy side: **nothing ever runs the
explicit fetch in production.**

### What actually happens on deploy

`models_dir` defaults to `Rails.root/tmp/essentia_models` (`app/jobs/enrich_album_job.rb:6`,
`app/services/mood_grounding_service.rb:11`, `lib/tasks/enrichment.rake:19,32`). `deploy.yml`
declares one volume, `vibe_doctor_storage:/rails/storage`, and sets no `ESSENTIA_MODELS_DIR`.
The `Dockerfile` installs `essentia-tensorflow` but has no model fetch or bake step.

So `/rails/tmp/essentia_models` is empty in every deployed container, and nothing populates it.

The first enrichment raises:

    Sonance::ConfigurationError: model digest mismatch: <filename>

And that error is **not rescued**. `ConfigurationError < FatalError < Error`
(`lib/sonance/errors.rb:23`), which is a *sibling* of `TrackError`, not a subclass.
`MoodGroundingService` rescues only `Sonance::TrackError` (`:116`, `:129`) and `Faraday::Error`
(`:119`). The error propagates and fails the job.

### Revised severity

| Claim as filed | Status |
|---|---|
| ~3.6 MB re-downloaded every deploy | **False** — nothing downloads |
| Container needs egress to essentia.upf.edu | **False** — it needs no egress at all |
| Wasteful but cheap, digest-verified | **False framing** — it is not wasteful, it is broken |

This is not a "wasteful re-download" issue. **Audio grounding cannot work in production at all
as currently configured.** That makes this unambiguously deploy-blocking, which is what I had
already called it, but for the wrong reason.

The remedy space is also different from what I described. Because there is no runtime download,
a persistent volume alone does **not** fix this — an empty persistent volume is still empty.
Whatever is chosen must actually *place the model files*, either by baking them into the image
at build time or by an explicit provisioning step whose failure is visible at deploy time rather
than at first enrichment.

Two constraints are unchanged: the SHA-256 and `byte_length` verification must stay meaningful
wherever the bytes come from, and the `DOWNLOAD_HOST` allowlist stays.

### Attribution

Filed on a mechanism I inferred rather than derived. The Principal's premise check
(`git grep` found no `fetch!` in the app) is what caught it; I then verified every line cited
above myself. Recording it here because the issue text would otherwise send an implementer to
build a persistent volume that would not fix the defect.
