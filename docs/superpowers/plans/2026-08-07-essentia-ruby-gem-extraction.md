# Plan: Extract Essentia mood extraction into a Ruby gem

Date: 2026-08-07
Status: **Phases 1–3 built. Phase 3 awaiting the human merge checkpoint.**

| Phase | State |
| --- | --- |
| 0 — decisions | ✅ resolved (§6) |
| 1 — golden fixtures | ✅ merged to local `main` (`d84ca2d`) |
| 2 — `mood_probe` gem | ✅ published, [github.com/Lhosb/mood_probe](https://github.com/Lhosb/mood_probe) @ `5360f8f`, 66 examples, 18 mutations killed |
| CI | ✅ authored (`96e546f`) — rspec + in-image `:essentia` jobs, red lint fixed. **Never executed**; needs a push |
| 3 — app on the gem | ⏸ `feat/essentia-gem-phase-3` @ `7138e9e`, all 5 Tier-1 gates PASS-WITH-NITS, **held for merge sign-off** |
| 3.5 / 4 / 5 | deferred — see §5 |

Reviews with line-level evidence: `/tmp/maestri-reviews/ESSENTIA-GEM/{principal,spec,test,security,quality}.md`

**Phase 3 took five fix rounds.** Each found something real, and the sequence is worth reading as a
pattern: the silent-`llm_only` degradation this plan set out to fix turned out to have **five**
distinct routes, four of which were only visible once the first was closed. Closing one made the next
reachable — the Faraday fold that closed route four is what made route five (`E1`) matter, because it
turned download failures into the guard's most reachable input and then discarded them whenever
YouTube was disabled.

> **Two pre-existing bugs this plan must not step on** — both independently verified by me against the
> code, not taken on report:
>
> 1. **`rake enrichment:backfill` cannot recover a failed album, today.**
>    `ENRICHMENT_TRANSITIONS["failed"] => %w[grounded]` (`album.rb:12`) forbids
>    `failed → matching_audio`, yet `needing_enrichment` includes `failed` (`album.rb:24`) and
>    `backfill` runs `EnrichAlbumJob` over exactly that scope (`enrichment.rake:3`), whose first act
>    is `start_matching!`. Only `reground_all` works, because it calls `reset_enrichment!` first,
>    which deliberately bypasses the transition table (`album.rb:46-50`).
> 2. **`valence`/`arousal` can legitimately fall outside `0.0..1.0`.** They come from
>    `model/Identity`, an unbounded regression head, rescaled `(x - 1.0) / 8.0` with **no clamp**
>    (`essentia_extract.py:19,43-44`). `MoodVector` validates `0.0..1.0` (`mood_vector.rb:9`), so an
>    emoMusic output of 0.97 or 9.2 makes `mood_vector.update!` raise → the album is marked failed →
>    and per bug 1 it can then only be recovered by `reground_all`.
>
> Bug 1 is what makes Phase 3's "fail loudly" dangerous: without a fix, loud failure is
> **irreversible** failure, which is worse than today's silent `llm_only`. See Phase 3.
>
> **Status:** Bug 1 fixed in Phase 3 — `ENRICHMENT_TRANSITIONS["failed"]` is now
> `%w[matching_audio grounded]`, with a round-trip spec. Bug 2 closed in Phase 2 as a side effect of
> the gem's `Features` clamp: `valence`/`arousal` are clamped into `0.0..1.0` before they ever reach
> `MoodVector`, so the validation can no longer be tripped by an unbounded regression output.

---

## 1. What Essentia is

Essentia (Music Technology Group, Universitat Pompeu Fabra) is an open-source **C++** library for
audio analysis and music information retrieval, with official **Python**, **JavaScript (WASM)**, and
CLI bindings. There is no Ruby binding, official or third-party — a RubyGems search for `essentia`
returns nothing related.

Beyond DSP algorithms it ships TensorFlow inference wrappers plus a catalogue of pretrained models
at `https://essentia.upf.edu/models/`, distributed as `.pb` (TF protobuf), `.onnx`, `.json`
metadata, and `tfjs.zip`.

### Licensing — read this before anything else

| Component | License | Commercial use |
| --- | --- | --- |
| Essentia library | AGPL-3.0 ("for non-commercial applications") | Requires a proprietary license from MTG (`mtg-info@upf.edu`) |
| Pretrained models | CC BY-NC-**SA** 4.0 per `models.html`; the licensing page states BY-NC-**ND** 4.0 | Requires a proprietary license from MTG |

Both are **non-commercial by default**, and the two MTG pages disagree on SA vs ND for the models —
that ambiguity matters because ND would bar redistributing modified weights.

**Where this app stands (decided 2026-08-07):** Vibe Doctor is **not** a commercial app and there
are no current plans for it to be. Today's usage is therefore inside both default grants, and no MTG
contact is needed. Remaining obligations and future risks:

- **AGPL §13 applies even non-commercially.** Serving a network application whose image contains
  Essentia means offering network users the corresponding source of the AGPL work. In practice this
  is cheap and already nearly satisfied: Essentia is installed unmodified from a pip wheel and runs
  as a separate process, so the obligation is to point at upstream — it does **not** reach into Vibe
  Doctor's own source, which neither links nor derives from Essentia.
- **A commercial pivot is the real exposure.** It would require licensing *both* the library and the
  models from MTG. This is what makes Phase 4 strategic rather than cosmetic — see §5.
- **A public gem must not carry the weights.** Redistributing NC-licensed models from RubyGems is
  the one line not to cross, and publishing is a stated future goal.

**Design consequence, adopted below:** the gem ships **no Essentia code and no model weights**. It
defines the interface, resolves a models directory the operator supplies, and can *optionally*
download weights on the operator's instruction. That keeps the gem itself MIT-clean, makes it
publishable on day one, and leaves the license posture entirely an application decision.

---

## 2. How this app uses Essentia today

### The two files

**`script/essentia_extract.py`** (65 lines) — a one-shot CLI. Per invocation:

1. `MonoLoader` decodes one audio file to mono @ 16 kHz.
2. `TensorflowPredictMusiCNN` on `msd-musicnn-1.pb`, output node `model/dense/BiasAdd`, produces
   per-patch embeddings.
3. Four classification heads via `TensorflowPredict2D` at `model/Softmax`, mean over patches,
   taking a fixed positive index per head: `danceability[0]`, `mood_acoustic[0]`,
   `mood_relaxed[1]`, `mood_happy[0]`.
4. `emomusic-msd-musicnn-2.pb` at `model/Identity` gives valence/arousal on emoMusic's 1–9 scale,
   rescaled to 0–1 as `(x - 1) / 8`.
5. Prints one JSON object with six floats to stdout.

**`app/services/essentia_feature_extractor.rb`** (24 lines) — `Open3.capture3` around that script,
raising `EssentiaFeatureExtractor::Error` on non-zero exit or unparseable JSON, then
`JSON.parse(stdout).transform_keys(&:to_sym).transform_values(&:to_f)`.

### The one consumer

`MoodGroundingService` is the **only** production call site (`app/services/mood_grounding_service.rb:7`,
with rescues at `:74` and `:83`). It constructs the extractor with
`models_dir: ENV.fetch("ESSENTIA_MODELS_DIR", Rails.root.join("tmp", "essentia_models"))`, then:

- tries iTunes previews (`ItunesPreviewMatcher`) → downloads each preview via Faraday to `tmp/` →
  `analyze` → deletes the file;
- falls back to YouTube clips (`YoutubeClipMatcher` → `yt-dlp`, 45 s from the 60 s mark) → `analyze`
  → deletes the clip;
- averages up to `GROUNDING_TRACKS_PER_ALBUM` (default 4) track vectors into mean + population
  stddev per head (`#aggregate`);
- on total failure returns `default_attrs` — all six heads at `0.5`, `mood_source: "llm_only"`.

Downstream, the six floats are `MoodVector::MOOD_HEADS`, consumed by `MoodVector#distance_to`,
`MoodVectors::VibePhraseBuilder`, and `AlbumEmbeddingService`. The same six-dimension schema is what
`QueryUnderstandingClient` asks an LLM to emit for free-text queries — which is the whole point of
the design, so **the output contract is not negotiable**: symbol-keyed floats in `0.0..1.0` for
exactly `valence, arousal, danceability, mood_acoustic, mood_relaxed, mood_happy`.

### Deployment and weights

- Six `.pb` files (~3.6 MB, `msd-musicnn-1.pb` is 3.2 MB of it) are **committed to git** under
  `tmp/essentia_models/`, kept alive by explicit negations in both `.gitignore` and `.dockerignore`.
- `Dockerfile:26-31` installs `python3 python3-venv ffmpeg`, then
  `pip install "essentia-tensorflow==2.1b6.dev1389" "yt-dlp"` into `/usr/local/essentia-venv`, and
  prepends that venv to `PATH`.
- Nothing in the repo fetches or checksums the weights — no rake task, no downloader.
- `lib/tasks/enrichment.rake` carries `reground_all`, whose own comment records that "production ran
  without a working essentia toolchain, so none of them ever got real audio analysis."

### Test coverage

`spec/services/essentia_feature_extractor_spec.rb` (36 lines) stubs `Open3.capture3` for three
cases: happy path, non-zero exit, invalid JSON. `spec/services/mood_grounding_service_spec.rb` uses
an `instance_double`. **Nothing exercises the Python script, a real model, or real audio** — there
is no test that would catch a change in the numbers Essentia returns.

---

## 3. Problems worth fixing while extracting

These are the reasons to do more than a copy-paste into a gemspec. Each has a named remedy in §5.

1. **`Rails.root` coupling.** `SCRIPT_PATH = Rails.root.join(...)` cannot be packaged as-is.
2. **Silent zeros.** `transform_values(&:to_f)` maps a missing or non-numeric head to `0.0`. A
   partially-broken script yields a *plausible* mood vector — `0.0` is a legal value — that is then
   persisted and used for recommendations. No schema check, no range check.
3. **No subprocess timeout.** `Open3.capture3` has no time limit. A wedged Python process pins a
   Solid Queue worker indefinitely.
4. **One process spawn per track.** Four tracks per album means four interpreter starts, four TF
   session initializations, and four loads of the 3.2 MB embedding graph. This is the dominant cost
   of enrichment and the single biggest available speedup.
5. **Undifferentiated errors.** One `Error` class covers "this file will not decode" (expected —
   skip the track) and "the models directory is empty" (a config fault that should be loud). Because
   `MoodGroundingService` rescues both identically, a misconfigured deploy degrades silently to
   `llm_only` — exactly the failure the `reground_all` comment describes.
6. **No model provisioning or verification.** Weights-in-git works today but ties model updates to
   app releases, and there is no checksum to detect a truncated or wrong file.
7. **Fragile dependency pin.** `essentia-tensorflow==2.1b6.dev1389` is a pre-release dev build
   chosen for one image's manylinux wheel. There is no macOS/arm64 wheel, so the extractor cannot
   run locally on the dev machines this repo targets (`.tool-versions` pins python 3.11.6).

---

## 4. Options considered

### Option A — Wrapper gem around the existing Python CLI  ✅ *recommended for phase 1*

Gem vendors `mood_probe_extract.py`, resolves the models dir, adds timeout, typed errors, and a
validated value object. Runtime still requires Python + `essentia-tensorflow`.

- **Pro:** numerically identical to today; smallest diff; fixes problems 1, 2, 3, 5, 6 immediately.
- **Con:** Python and AGPL Essentia stay in the image; problem 4 only partly addressed (batching
  several files into one invocation helps; it is still an out-of-process call).

### Option B — Pure Ruby via ONNX Runtime  ✅ *recommended for phase 4, behind a gate*

Verified available: every model this app uses has an `.onnx` sibling —
`feature-extractors/musicnn/msd-musicnn-1.onnx`,
`classification-heads/danceability/danceability-msd-musicnn-1.onnx`, and the same pattern for the
mood heads and emomusic. The Ruby side would be `onnxruntime` (0.11.5, MIT, ~2.9M downloads) +
`numo-narray`, with `ffmpeg` shelled out for decode/resample to 16 kHz mono.

- **Pro:** no Python in the inference path, no AGPL Essentia in the image, model loaded **once** per
  process (fully fixes problem 4), materially smaller image, in-process error handling.
- **Con — and this is the entire risk:** `TensorflowInputMusiCNN`'s log-mel front end must be
  reimplemented in Ruby and must match Essentia numerically. Essentia's own algorithm reference page
  documents neither the frame/hop size, window, mel band count and range, nor the log compression
  formula; the parameters have to be read out of
  `src/algorithms/standard/tensorflowinputmusicnn.cpp`. MTG issue
  [#1471](https://github.com/MTG/essentia/issues/1471) is an unresolved report of someone failing to
  reproduce these mel-spectrograms in librosa ("results are way off"). A near-miss front end
  produces confidently wrong mood vectors, not an error.
- **Therefore:** this option ships only if it passes the parity gate in §5 Phase 4. Otherwise it is
  abandoned, not approximated.

### Option C — HTTP sidecar service

Python FastAPI container; the gem becomes a Faraday client.

- **Pro:** model loaded once; Python and AGPL isolated from the Rails image; natural Kamal accessory.
- **Con:** a new deployable and a network hop for a single-consumer, batch-oriented workload. Worth
  revisiting only if extraction moves off-box or is shared with another app.

### Option D — Native extension binding Essentia's C++ API

**Rejected.** Compiling Essentia plus the TensorFlow C API per platform, with direct AGPL linkage,
for one call site returning six floats. The maintenance cost is out of all proportion.

---

## 5. Recommended plan

Two-stage: **move the boundary first without changing the numbers, then change the implementation
behind that boundary.** Each phase is independently shippable and independently revertible.

Gem name: **`mood_probe`** — deliberately not "essentia", both because the gem contains none of it
and to avoid implying MTG endorsement.

### Location and wiring (decided 2026-08-07)

Three independent choices:

| Axis | Decision |
| --- | --- |
| **Local dev checkout** | `~/projects/gems/mood_probe` — sibling of this repo, its own git repo |
| **Remote** | public GitHub repo, created in Phase 2 |
| **RubyGems** | later; a two-line change when wanted |

The local checkout location has one consequence that has to be designed around: **`~/projects/gems`
is outside this repo's Docker build context.** A plain `gem "mood_probe", path: "../gems/mood_probe"`
resolves fine for local `bundle install` but makes the image build fail — `COPY . .` cannot reach a
sibling directory, and Phase 3's definition of done includes a production reground. So the app
consumes the gem by **git source**, and local development gets path-like ergonomics via Bundler's
local override:

- `Gemfile`:
  ```ruby
  gem "mood_probe", git: "https://github.com/Lhosb/mood_probe.git"
  ```
  `Gemfile.lock` pins an exact revision, so image builds are reproducible. The build stage already
  installs `git` (`Dockerfile:45`), and a public repo means no build-time token.
- Local override, set once:
  ```sh
  bundle config set --local local.mood_probe ~/projects/gems/mood_probe
  ```
  Edits in `~/projects/gems/mood_probe` then take effect in this app immediately, with no
  re-bundling — the same day-to-day feel as a `path:` source.
- **The one wrinkle to know:** with a local override active, Bundler writes the *local* checkout's
  HEAD SHA into `Gemfile.lock` and requires the branch to match. That SHA must be **pushed** before
  CI or a Docker build can resolve it. Treat "push the gem, then commit the app's lockfile" as the
  standing order; a stale-lock failure here is confusing if you haven't seen it before.
- **RubyGems, when wanted:** `gem push`, then swap the `git:` source for a version constraint.
  Nothing else in the app moves. Keeping the gem MIT-clean and weights-free from the start (§1) is
  what keeps that door open.

```
~/projects/gems/mood_probe/
  mood_probe.gemspec
  lib/mood_probe.rb
  lib/mood_probe/version.rb
  lib/mood_probe/features.rb              # frozen value object; 6 keys required. Softmax heads strict
                                          #   0.0..1.0; valence/arousal CLAMPED (see below)
  lib/mood_probe/result.rb                # path / ok? / features / error — analyze_all's element type
  lib/mood_probe/extractor.rb             # backend-agnostic public API
  lib/mood_probe/errors.rb                # Error
                                          # ├── TrackError  — UnreadableAudioError, TimeoutError
                                          # └── FatalError  — ConfigurationError, BackendError
  lib/mood_probe/model_registry.rb        # filenames, output nodes, positive indices, SHA-256, source URLs
  lib/mood_probe/model_store.rb           # resolve / verify / (opt-in) download weights
  lib/mood_probe/backends/essentia_python.rb
  lib/mood_probe/backends/onnx.rb         # phase 4
  python/mood_probe_extract.py            # vendored CLI (phase 2)
  exe/mood-probe                          # `analyze FILE`, `models fetch`, `models verify`
  spec/fixtures/                          # audio + golden JSON
```

Public API:

```ruby
extractor = MoodProbe::Extractor.new(
  models_dir: dir,
  timeout_per_file: 60,          # budget = startup_grace + timeout_per_file * n
  python_executable: "python3"   # injectable — hardcoding it in a gem is an operator trap
)
extractor.verify!                            # preflight: 6 models present, digests match. No audio.
features = extractor.analyze(path)           # => Features; RAISES on failure
results  = extractor.analyze_all(paths)      # => Array<Result>; never raises per-file
```

`analyze_all` returns `Result` objects rather than bare `Features` because positional alignment and
per-file error reporting are the whole point. **Binding contract** — holds whether the implementation
is batched or a plain loop:

- Same length as `paths`, aligned 1:1 by position. Accepts `String` **or** `Pathname`; the app passes
  both (`mood_grounding_service.rb:68,73` vs `:82`).
- `Result#path`, `#ok?`, `#features`, `#error` — never both `nil`, never both set.
- **Per-file failures never raise**: `ok? == false` plus a `TrackError`.
- **`ConfigurationError` raises before any file is touched** — load all six graphs first, so a bad
  models dir costs zero downloads.
- `analyze(path)` raises the `Result`'s error instead of returning it.
- Timeout **scales per file**; a flat batch timeout is batch-unaware and wrong.
- Wire protocol NDJSON, one line per path, flushed as each completes. Exit `0` = run completed
  (per-file failures do *not* change it), `2` = config fault, `1` = crash. Partial output is usable.

Error hierarchy is **intent-shaped**, so callers rescue a category instead of enumerating classes:

```
MoodProbe::Error
├── TrackError  ── UnreadableAudioError, TimeoutError    # skip this track, keep going
└── FatalError  ── ConfigurationError, BackendError      # stop; the whole run is invalid
```

`MoodGroundingService` rescues `MoodProbe::TrackError` only; everything else propagates.

**`Features` validation — clamp vs raise.** The four classification heads are softmax-bounded
(`essentia_extract.py:17`) and get strict `0.0..1.0`. `valence`/`arousal` are **not** — see
pre-existing bug 2 at the top of this document. Therefore:

- **Clamp** `valence`/`arousal` into `0.0..1.0`, as a documented and tested step.
- **Raise** only on a missing key, a non-finite value, or a value outside a sanity window
  (`-0.5..1.5`) — that indicates a broken model, not boundary rounding.
- Problem 2's actual target — a *missing* head silently becoming `0.0` via
  `transform_values(&:to_f)` (`essentia_feature_extractor.rb:20`) — is closed by the presence check
  alone. Strict range checking on the regression heads never fixed it and would reject valid output.

**`EssentiaFeatureExtractor` is deleted**, not retained as an adapter. `MoodGroundingService` depends
on `MoodProbe::Extractor` directly; constructor injection (`mood_grounding_service.rb:4-18`) is
untouched. CLAUDE.md says where an integration wrapper *belongs*, not that every integration needs one
of ours in front of it — `MoodProbe::Extractor` **is** the wrapper. Decisive: Phase 3 already has
`MoodGroundingService` rescuing `MoodProbe::*` directly, so the seam would encapsulate nothing while
costing a file, a spec, and a name that lies.

Compatibility requirement: `Features#to_h` is symbol-keyed with exactly `MoodVector::MOOD_HEADS`, so
`MoodGroundingService#aggregate` is untouched.

### Phase 0 — Decision gate (no code)

Resolve §6. Licensing posture determines gem visibility and whether MTG must be contacted; it does
not block phases 1–3 for a private path gem, but it does block any publication.
**Escalate to the user.**

### Phase 1 — Golden fixtures  · Tier 3 (test-only)

Do this **first**; it is the only thing that makes every later phase verifiable.

- 3–5 short, license-clean audio fixtures (own recordings or CC0), plus a deliberately corrupt file.
- Run each through the *current* `script/essentia_extract.py` on a machine with a working
  `essentia-tensorflow`; commit the six floats as JSON at full precision.
- A spec tagged `:essentia` that runs the real pipeline and asserts against those goldens, skipped
  when the backend is absent so the default suite stays hermetic.
- **The tagged spec must be a real gate, not a comment.** With no arm64 wheel, `:essentia` is skipped
  on every dev Mac *and* in all of CI — "always skipped" gates nothing. So Phase 1 must name the
  exact `docker build` / `docker run` commands **verbatim and copy-pasteable**, such that a reader
  reproduces the goldens from that text alone.
- **Record observed wall-clock per fixture.** It is the only measurement that can justify a defensible
  `timeout_per_file` default, and the only baseline that could ever justify batching.
- **DoD:** goldens committed; tagged spec passes in-image, skips cleanly where essentia is absent;
  `bundle exec rspec` green unchanged; verbatim docker commands recorded; wall-clock recorded.

**Status: COMPLETE** — `feat/essentia-gem-phase-1`, BASE `7628e73` → HEAD `d84ca2d`, 13 files
`+138`, all under `spec/`. Four synthetic 10 s/16 kHz mono WAV fixtures (440 Hz sine, seeded white
noise, log chirp, rhythmic clicks) at 1.2 MB total, byte-identical on regeneration, plus a 32-byte
undecodable `.m4a`. Mac suite 251/0 with `:essentia` filtered (independently re-run by me); five
tagged examples green in-image. Wall-clock 1.81–1.96 s per fixture per process (amd64 emulation).
`bash -lc` → `bash -c` was a real catch: a login shell reset the image PATH and selected
`/usr/bin/python3`, which has no Essentia.

### Phase 2 — Build the gem with the Option A backend  · Tier 2

- Scaffold `~/projects/gems/mood_probe` as its own public GitHub repo (MIT license, `NOTICE` naming
  Essentia and the CC BY-NC-SA/ND model terms without shipping either); move
  `script/essentia_extract.py` in as
  `python/mood_probe_extract.py`, resolving its path relative to `__dir__`, not `Rails.root`.
- Ship the **`analyze_all` interface and its full contract** (above), but implement it as a plain
  loop. **The batched implementation is deferred to a new Phase 3.5.** Batching here would violate
  this plan's own principle of moving the boundary without changing the numbers: Essentia is C++, so a
  segfault on track 3 of 4 loses all four results, which flips `track_coords.empty?`
  (`mood_grounding_service.rb:45`) and drops the album to the YouTube path — yielding a *different*
  `mood_source`. Nothing measured supports calling per-spawn cost "dominant" (Phase 1 measured
  ~1.8–2.0 s per fixture, so ~8 s per 4-track album — real but not a crisis), §6 records no latency
  problem, and Phase 4 obsoletes the optimization anyway. When batching does land it must retry the
  unemitted remainder once, one file per invocation.
- Extend the Python CLI to accept **multiple audio paths** and emit NDJSON per the wire protocol
  above, so Phase 3.5 is a gem-side change only.
- **Clamp tests must be synthetic unit tests, not fixture-driven.** Phase 1's four goldens all land
  valence/arousal in 0.22–0.73, so no committed fixture exercises the out-of-range boundary that the
  unbounded emoMusic head can produce. Cover `-0.004`, `1.025`, `NaN`, and a missing key directly.
- `Features` validates: all six keys present, each a finite Float in `0.0..1.0`. Anything else
  raises. This closes the silent-`0.0` hole (problem 2).
- Replace `Open3.capture3` with a timeout-bounded spawn that kills the child on expiry
  (`TimeoutError`) — problem 3.
- Classify the script's failures into `UnreadableAudioError` vs `ConfigurationError` by exit code,
  set deliberately in the Python side — problem 5.
- `ModelRegistry` records each file's SHA-256 and `essentia.upf.edu` URL; `ModelStore#verify!` checks
  digests and `#fetch!` downloads on explicit instruction only, never implicitly at analyze time —
  problem 6. Attribution and the CC BY-NC-SA/ND notice go in the gem's `NOTICE`.
- Gem spec suite: unit tests stub the subprocess; the Phase 1 goldens run through the gem's own
  `:essentia`-tagged spec.
- **DoD:** gem suite green; golden parity exact; `exe/mood-probe analyze` works from a bare checkout
  given a models dir; RuboCop clean.

### Phase 3 — Point the app at the gem  · **Tier 1**

Tier 1 by two triggers: a **new dependency**, and a change to the code path that **writes
`mood_vectors`** rows. Principal Engineer reviews before implementation; human merge checkpoint
applies.

- `Gemfile`: `gem "mood_probe", git: "https://github.com/Lhosb/mood_probe.git", branch: "main"`
  — **pin the branch explicitly.** Bundler's local override requires the checkout to match the named
  branch, and omitting `branch:` is the top source of confusing errors in this setup. Plus a README
  note on the `bundle config set --local local.mood_probe ~/projects/gems/mood_probe` dev override.
- **Delete `EssentiaFeatureExtractor` and its spec** — see §5, which is authoritative. (A stale bullet
  here previously said to keep it as a delegating seam; that predated Keystone's review and was struck
  2026-08-07 after Plumb flagged the contradiction. Constructor injection in `MoodGroundingService` is
  untouched either way, so `#aggregate` and every downstream consumer see the identical hash shape.)
- `MoodGroundingService`: rescue `MoodProbe::TrackError` per track (log and skip, as today) but let
  `MoodProbe::FatalError` **propagate** so a models-dir
  misconfiguration fails the job loudly instead of degrading to `llm_only`.
- Delete `script/essentia_extract.py` and its now-duplicated spec; rewrite
  `essentia_feature_extractor_spec.rb` against the gem's double.
- Dockerfile: unchanged in this phase (same venv, same pin). **Weights stay in git — permanently, not
  just "for now."** A build-time fetch would make `essentia.upf.edu` a build-time single point of
  failure for every emergency redeploy; git already content-addresses the blobs so truncation is
  near-impossible; and problem 6's real complaint (no checksum) is fully closed by the Phase 2
  `ModelRegistry` SHA-256 + `ModelStore#verify!` **without moving anything**. Not worth a tier
  escalation.
  - Cheap separate PR, explicitly **not** part of Phase 3: `git mv tmp/essentia_models
    models/essentia`. `tmp/` is disposable by convention, and 3.6 MB of tracked production assets
    currently live there behind ignore negations (`.gitignore:36-38`, `.dockerignore:33-35`).
  - **TRIPWIRE:** `Lhosb/vibe-doctor` is **PRIVATE** (verified via `gh repo view`). That is the only
    reason committing CC BY-NC weights is not redistribution. **Making this repo public requires
    removing them from git history first** — not just deleting them from `HEAD`. The `mood_probe` gem
    repo is public and must therefore never contain weights (§1).
**Prerequisite — an "all tracks failed identically" guard.** Raised by Litmus during Phase 2 review, and it
closes the last route to the silent-`llm_only` bug. `InferenceError` is correctly a `TrackError`, because a
single bad file genuinely should be skipped. But a *deterministic* fault — a bad graph, OOM — hits every file
and therefore surfaces as N per-track errors with exit 0. `MoodGroundingService` then sees
`track_coords.empty?` (`:45`), returns `nil`, falls through to YouTube, and finally to `default_attrs` at
`mood_source: "llm_only"`. That is the same silent degradation the schema-drift ruling closed on the
*features* half of the wire, arriving instead through the *inference* door.

Blanket-fatal is the wrong fix — it breaks the legitimate per-file case. Instead:

- App-side: when **every** track fails and they fail with the **same** error class, escalate rather than
  silently degrade. "Some tracks failed" and "nothing worked and it looks systematic" are different events
  and must not share a code path.
- Gem-side: a README note making this a documented caller obligation, since the gem cannot distinguish the
  two cases from inside a single run.

**Prerequisite — the state-machine fix must land with this phase, not after it.** Per bug 1 at the
top of this document, propagating `FatalError` without it means one bad models dir marks the whole
catalogue `failed`, and `backfill` then cannot recover any of it. Required:

- (a) `Extractor#verify!` preflight, called once at the top of `run_enrichment` **and** in
  `EnrichAlbumJob` before `start_matching!` — so a misconfiguration fails on album zero at zero HTTP
  cost.
- (b) `run_enrichment` re-raises `MoodProbe::FatalError` instead of counting it as one album's
  failure and continuing through the catalogue (`enrichment.rake:24-29`).
- (c) Add `"matching_audio"` to `ENRICHMENT_TRANSITIONS["failed"]`, with a model spec covering the
  `failed → matching_audio → grounded` round trip.

Without (c), "fail loudly" means "fail irreversibly" — strictly worse than today's silent
`llm_only`. Do not ship propagation without it.

- **DoD — two separate checks; the old single "1e-6 on real albums" gate was unsatisfiable and has
  been replaced.** It asked for ≥5 albums at `mood_source: essentia_itunes` when
  `enrichment.rake:7-9` records that production never had a working toolchain (so there may be
  **zero**), and `analyze_remote_track` re-downloads previews live from a non-deterministic
  `ItunesPreviewMatcher` (`:39`, `:67-79`) — making album-level numeric equality impossible by
  construction. Instead:
  1. **Parity gate:** run the Phase 1 fixtures through the old path and the new path *in the same
     container* and assert **bit-identical** output. `1e-6` is needlessly loose for a phase that
     translates code without touching the model.
  2. **Smoke test:** reground ≥5 real albums and assert `mood_source` lands, heads are in range,
     `spread` is populated, and no exceptions — **no numeric equality assertions.** Report the
     vectors for eyeballing.
- Also: full suite green; `failed → matching_audio` round-trip spec; `run_enrichment` aborts on
  `FatalError`; a preflight demo showing **zero iTunes HTTP calls** against an empty models dir;
  `EssentiaFeatureExtractor` and its spec deleted. Report BASE/HEAD SHAs.
- Keep the `ESSENTIA_MODELS_DIR` env var name through this phase — renaming it is deploy surface,
  which is the wrong thing to churn inside a Tier-1 change.

### Phase 4 — ONNX backend  · Tier 2, separate PR, opt-in

**Why this is worth doing even with no latency pain.** ONNX Runtime is MIT. Essentia is AGPL. So
Phases 4–5 remove the *only AGPL component* from the deployed image, leaving just the CC-NC
**models** — which are also the easier half to license. If Vibe Doctor ever goes commercial, that
turns an MTG negotiation over "library + models" into one over "models only," and removes the AGPL
§13 source-offer obligation outright. Combined with the free wins (model loaded once instead of four
times per album, several hundred MB off the image, and local macOS/arm64 development becoming
possible for the first time), this is a cheap option on a future pivot rather than a perf micro-fix.
It stays *after* Phase 3 because the parity risk below is real and unresolved upstream.

- Read the mel parameters out of Essentia's `tensorflowinputmusicnn.cpp` (sample rate, frame/hop,
  window, mel band count and range, log compression, patch size, patch hop) and record them as
  documented constants in the gem — not as folklore.
- Implement the front end on `numo-narray`; decode/resample via `ffmpeg`; run `msd-musicnn-1.onnx`
  and the head models through `onnxruntime`, session cached for the process lifetime.
- Selectable via `MoodProbe::Extractor.new(backend: :onnx)`; Option A remains the default.
- **Gate — merge only if this passes:** for every Phase 1 fixture, all six heads from the ONNX
  backend agree with the golden Essentia values within `1e-3` absolute. If the front end cannot be
  reproduced, close the branch and keep Option A. Do not relax the tolerance to make it pass.
- **Invariant you inherit, flagged by Plumb during Phase 2 review.** The Python backend's non-finite guard
  sits *inside* the per-file `try`, so `math.isfinite` applied to a non-number would raise `TypeError` and be
  classified as `inference_error` — a **`TrackError`** — where the schema ruling says a non-numeric value is
  **fatal**. It is unreachable in the Python backend only because `analyze()` wraps every value in `float()`
  before the check. **An ONNX backend does not inherit that coercion for free.** Either coerce to float before
  the finiteness check, or classify non-numeric explicitly as `SchemaError`. This is precisely the kind of
  invariant that survives a rewrite as a silent behaviour change.
- **Compare the `msd-musicnn` embedding layer BEFORE comparing the six heads.** A mismatch there
  localises the bug to the mel front end immediately, instead of leaving you staring at six wrong
  floats with no idea which stage produced them. On the #1471 risk this is the difference between a
  day and a week. Report embedding-layer parity first, head parity second.
- Also report: per-album wall-clock and peak RSS, Option A vs Option B. Phase 1's baseline is
  ~1.8–2.0 s per 10 s fixture per process under amd64 emulation.
- **DoD:** embedding-layer parity reported; head gate passed with the numbers shown; or the option
  formally abandoned with the parity failures documented.
- Why the `1e-3` gate is the right size: `MoodVector#distance_to` is 6-D Euclidean against
  `MAX_DISTANCE = sqrt(6) ≈ 2.449`, so worst-case `1e-3` drift on all six heads moves a distance by
  ~0.1% — invisible downstream. Do not let Phase 5 creep forward ahead of a full production reground.

### Phase 5 — Retire the TensorFlow wheel  · **Tier 1** (Dockerfile + dependency + deploy)

Only after the ONNX backend has been default in production through one full reground cycle.

- Drop `essentia-tensorflow==2.1b6.dev1389`; add `onnxruntime` to the Gemfile; keep the `.onnx`
  weights.
- **`python3` and the venv stay** — `YoutubeClipMatcher` shells out to `yt-dlp`, which is Python.
  The win here is deleting the TensorFlow wheel (several hundred MB), not deleting Python.
- Side benefit: local dev on macOS/arm64 becomes possible for the first time (problem 7), since
  `onnxruntime` has arm64 binaries where `essentia-tensorflow` has no wheel at all.
- **DoD:** image size before/after; `reground_all` on a sample produces vectors matching within the
  Phase 4 tolerance; Kamal deploy verified with real audio grounding in production.

### Sequencing

```
Phase 0 (decisions) ──▶ Phase 1 (goldens) ──▶ Phase 2 (gem, backend A) ──▶ Phase 3 (app swap)
                                                                                   │
                                                            Phase 4 (ONNX, gated) ─┘
                                                                     │
                                                            Phase 5 (drop TF wheel)
```

Phases 1–3 deliver the gem the request asks for and fix all seven §3 problems. Phases 4–5 are a
follow-on: not urgent (there is no latency complaint today), but justified by the licensing argument
in Phase 4 plus welcome speed and image-size wins. Attempt Phase 4 only after Phase 3 is in
production, and let its parity gate decide its fate.

### Rough effort

| Phase | Size |
| --- | --- |
| 1 — goldens | small; gated on a machine with working essentia |
| 2 — gem + backend A | medium — the bulk of the work |
| 3 — app swap | small diff, heavier verification |
| 4 — ONNX backend | medium–large, genuinely uncertain (the mel front end) |
| 5 — drop TF wheel | small code, real deploy risk |

---

## 6. Decisions — resolved 2026-08-07

1. **Commercial posture:** not a commercial app, no current plans to become one. Proceed under the
   default AGPL / CC-NC grants; no MTG contact needed now. Revisit only on a commercial pivot, at
   which point Phase 4 will have cut the problem in half (see §1 and Phase 4).
2. **Gem location:** developed locally at `~/projects/gems/mood_probe`, alongside this repo rather
   than inside it.
   **Remote:** a public GitHub repo is fine and gets created in Phase 2.
   **RubyGems:** deferred, and stays a two-line change whenever wanted.
   The app consumes it via a `git:` source with a Bundler local override — see §5 "Location and
   wiring" for why a `path:` source is not an option here.
3. **Performance:** no latency problem today, but improvements welcome. Phases 4–5 are scheduled as
   follow-on work rather than dropped, on the licensing rationale in Phase 4.

### Consequences captured elsewhere in this plan

- The gem must carry **no weights** — non-negotiable once publishing is on the table (§1).
- `~/projects/gems` is **outside the Docker build context**, so the app uses a `git:` source, not a
  `path:` source (§5).
- Phase 4 is reframed from optional perf work to a cheap hedge against a future commercial pivot.
