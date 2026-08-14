# ESSENTIA-GEM-V2 — Security and Supply-Chain Design Review

**Verdict:** The generalization is viable, but the architecture should not proceed without four hard constraints: consumers request only registered descriptor IDs; built-in model artifacts remain governed by an immutable digest manifest; subprocess output and every typed result shape are bounded and validated on both sides; and model packs are explicit operator choices because all reviewed MTG weights are non-commercial.

## Findings

### 🟠 High — CONFIRMED: the model licence is non-commercial, and official MTG sources conflict on ND versus SA

**Concrete failure scenario.** A public gem or application describes the weights as CC BY-NC-SA, redistributes or fine-tunes them on that basis, or enables them in a commercial deployment. MTG's dedicated licensing page says all Essentia models are CC BY-NC-ND 4.0 for non-commercial use, and the repository-wide model `LICENSE` contains the BY-NC-ND legal text. The models page and model `README.md`, however, say BY-NC-SA. This is a material conflict: ND prohibits sharing adapted weights, while SA permits adaptations subject to share-alike. Commercial use is prohibited under either statement without a proprietary licence.

**Attachment.**

- Current gem notice: `mood_probe/NOTICE:7-13` says model metadata identifies BY-NC-SA or BY-NC-ND "depending on the model." I found no per-model `license` field in the reviewed metadata; MTG applies a directory-wide licence instead.
- Current and proposed MusiCNN, Discogs-EffNet, and classification-head files are all hosted under the directory covered by `https://essentia.upf.edu/models/LICENSE`.
- Official licensing page: https://essentia.upf.edu/licensing_information.html
- Official directory licence: https://essentia.upf.edu/models/LICENSE
- Conflicting model repository summary: https://essentia.upf.edu/models/README.md and https://essentia.upf.edu/models.html

**Recommendation.**

1. Treat **CC BY-NC-ND 4.0** as the compliance floor unless MTG provides written clarification. Mark the SA/ND discrepancy explicitly rather than claiming model-dependent licences.
2. Keep weights out of the gem. An MIT gem may provide code and a manifest, but model installation must be an explicit operator action with the model licence, attribution, source URL, and commercial-use warning presented before download.
3. Do not ship a commercial-use mode for these packs without a configured acknowledgement that the operator has obtained the required proprietary licence.
4. Do not redistribute modified/fine-tuned weights under the public model licence. Preserve exact upstream bytes.
5. Update `NOTICE` during V2 so it does not make the unsupported "depending on the model" claim.

All reviewed current and proposed model files fall under the same directory-wide restriction:

| Family | Reviewed models | Licence conclusion |
|---|---|---|
| MusiCNN | `msd-musicnn-1`, current six heads, `mood_sad`, `mood_aggressive`, `mood_party`, `mood_electronic`, `voice_instrumental`, `tonal_atonal` | CC BY-NC-ND 4.0 compliance floor; non-commercial |
| Discogs-EffNet | `discogs-effnet-bs64-1`, `genre_discogs400`, `timbre`, `approachability_2c`, `engagement_2c` | CC BY-NC-ND 4.0 compliance floor; non-commercial |

The Essentia library is separately AGPLv3 for non-commercial applications, with proprietary licensing available: https://essentia.upf.edu/licensing_information.html. The gem correctly ships neither Essentia nor weights (`mood_probe/NOTICE:1-10`), but operators still own compliance for the separately installed runtime.

### 🟠 High — PLAUSIBLE: consumer-supplied registrations can become arbitrary file writes, SSRF, arbitrary graph loading, or unsafe native algorithm selection

**Concrete failure scenario.** The proposed runtime-registration API accepts a third-party or data-loaded descriptor definition containing `filename: "../../config/..."`, an arbitrary `source_url`, an absolute model path, or an algorithm/class name. The current store joins registry filenames directly beneath `models_dir`, downloads the registry URL, and moves the file to that joined path (`mood_probe/lib/mood_probe/model_store.rb:56-75`). If generalized without a trust boundary, a malicious registration can escape the model root, make network requests to internal addresses, overwrite a reachable file, or load an attacker-selected TensorFlow graph into native TensorFlow/Essentia code. Dynamic `getattr`/constant lookup of an algorithm name would add another code-selection surface.

Today this is not remotely reachable: the registry is a frozen Ruby constant (`mood_probe/lib/mood_probe/model_registry.rb:12-60`), the Python script uses fixed filenames and fixed Essentia classes (`mood_probe/python/mood_probe_extract.py:10-43`), and the app's only production integration is offline (`vibe-doctor/app/jobs/enrich_album_job.rb:4-44`; `vibe-doctor/app/services/mood_grounding_service.rb:6-21`). The proposed design changes that trust assumption.

**Recommendation.**

- Split **selection** from **registration**. The subprocess request may contain descriptor IDs only, never filenames, URLs, model paths, output nodes, Python names, or algorithm names.
- Keep built-in definitions in a gem-authored, frozen, versioned manifest. Resolve the same ID independently on the Ruby and Python sides and reject unknown, duplicate, missing, or extra IDs.
- Make custom registration explicitly **operator/developer trusted**, disabled by default, and declarative. It must not accept Python snippets, shell fragments, module/class names, Ruby blocks serialized across the boundary, arbitrary URLs, or arbitrary output-node discovery.
- Use a static algorithm enum and dispatcher in Python. Never instantiate Essentia algorithms using unrestricted `getattr`, `eval`, imports, or consumer-provided class names.
- Validate on both sides: conservative descriptor-ID grammar and length; unique IDs; known result type; declared exact/max dimensions; bounded dependency DAG with cycle detection; known algorithm enum; known model dependency; valid class/positive index; and type-specific native ranges.
- For custom model support, require an explicit local artifact plus operator-supplied digest under a separate `allow_custom_models` capability. Do not automatically fetch custom URLs.
- Resolve model destinations canonically under the configured model root; reject absolute paths, `..`, path separators in manifest filenames, symlink destinations/components, non-regular files, and canonical paths outside the root.
- Treat TensorFlow graphs as executable/native-parser inputs. A SHA-256 verifies identity, not safety; only approved built-in hashes should be loaded by default.

Audio paths are different: a local extraction library legitimately needs to read caller-selected audio outside the model root. Current app paths are generated temporary files for downloaded previews or matcher-created clips (`vibe-doctor/app/services/mood_grounding_service.rb:66-84,87-113`). Continue passing them as argv elements, but document that `analyze(path)` is a local-file read capability and must not be exposed directly to untrusted web parameters. Ruby and Python should both require an existing regular file; neither should reinterpret it as a model/config path.

### 🟠 High — CONFIRMED current limitation / PLAUSIBLE V2 DoS: widened NDJSON is unbounded and the finite-value guard breaks on vectors

**Concrete failure scenario.** A buggy or malicious extractor emits an embedding per audio patch, a very long future beat series, or a large stderr stream. `CommandRunner` currently calls `stdout.read` and `stderr.read` in threads and retains both complete strings (`mood_probe/lib/mood_probe/backends/essentia_python.rb:27-44`). A job worker can therefore be killed by memory exhaustion before Ruby reaches JSON validation. Timeout does not limit bytes produced before termination.

The existing schema is fixed and shallow:

- Ruby requires exactly one nonblank NDJSON line, checks only the path and presence of `features`, and returns the raw feature hash (`mood_probe/lib/mood_probe/backends/essentia_python.rb:150-164`).
- `MoodProbe::Features` requires exactly six scalar keys and calls `finite?` on each numeric (`mood_probe/lib/mood_probe/features.rb:3-20,29-51`). It cannot represent open typed descriptors.
- Python applies `math.isfinite(value)` only to each top-level scalar (`mood_probe/python/mood_probe_extract.py:107-126`). A vector value is a list, so this guard raises `TypeError` and becomes `inference_error`; if a future path bypasses that shallow guard, default `json.dumps` emits bare `NaN`.
- Confirmed boundary behavior: Python emitted `{"vector": [1.0, NaN]}` by default; Ruby `JSON.parse` rejected bare `NaN` with `JSON::ParserError`. Widening does not make NaN silently accepted, but it does reopen the seam inside nested values unless validation becomes recursive.

**Recommendation.**

1. Stream stdout and stderr through bounded readers. Stop and kill the existing subprocess group as soon as a stream exceeds its cap. Use separate limits for stdout and diagnostic stderr.
2. Define an absolute per-record and per-process byte limit. A few MiB is ample for fixed pooled 200/1280-dimensional embeddings and 400-class outputs; future `Series` must also have an item-count/duration limit.
3. Preserve NDJSON cardinality explicitly: `analyze` must return exactly one record for the requested path; batching must return exactly one record per requested path, with no duplicate, missing, unknown, or extra paths.
4. Validate the exact requested descriptor-ID set, not just the existence of a `features` member.
5. Apply type-specific schemas on both sides:
   - `Scalar`: numeric, finite, declared sanity range.
   - `Categorical`: value/classes constrained by the registered descriptor.
   - `Vector`: exact declared dimension, numeric finite elements, maximum dimension.
   - `Series`: maximum elements, recursively validated element shape, monotonic/bounded timestamps where applicable, no arbitrary nesting.
6. Recursively reject non-finite values in Python and Ruby. Emit with `json.dumps(..., allow_nan=False)` as a final Python-side fail-closed guard.
7. Validate provenance against the registry; do not trust arbitrary model/version strings returned by the subprocess.

### 🟡 Important — CONFIRMED: three proposed “Tier 1” candidates actually require the separate Discogs-EffNet model

**Concrete failure scenario.** Architecture treats `timbre`, `approachability`, and `engagement` as near-free heads on the already-computed 200-dimensional MusiCNN embedding (`mood_probe_gem_brainstorm_prompt.md:36-41`). Implementation then either feeds the wrong 200-dimensional tensor into heads that require 1280 dimensions, or silently introduces the Discogs-EffNet extractor, download, licensing, memory, and inference cost into the default pack.

Official metadata confirms:

- `tonal_atonal-msd-musicnn-1` takes a 200-dimensional MusiCNN embedding: https://essentia.upf.edu/models/classification-heads/tonal_atonal/tonal_atonal-msd-musicnn-1.json
- `timbre-discogs-effnet-1` takes a 1280-dimensional Discogs-EffNet embedding: https://essentia.upf.edu/models/classification-heads/timbre/timbre-discogs-effnet-1.json
- `approachability_2c-discogs-effnet-1` and `engagement_2c-discogs-effnet-1` likewise declare 1280-dimensional inputs:
  - https://essentia.upf.edu/models/classification-heads/approachability/approachability_2c-discogs-effnet-1.json
  - https://essentia.upf.edu/models/classification-heads/engagement/engagement_2c-discogs-effnet-1.json

Measured upstream artifact sizes:

| Pack addition | Downloaded bytes | Approximate MiB |
|---|---:|---:|
| Five requested extra MusiCNN heads | 412,290 | 0.39 |
| `tonal_atonal` MusiCNN head | 82,458 | 0.08 |
| Discogs-EffNet bs64 extractor | 18,366,619 | 17.52 |
| `genre_discogs400` head | 2,057,977 | 1.96 |
| `timbre` head | 514,458 | 0.49 |
| `approachability_2c` head | 514,458 | 0.49 |
| `engagement_2c` head | 514,458 | 0.49 |

Current committed Vibe Doctor models total 3,610,291 bytes (about 3.44 MiB). The core five extra MusiCNN heads are genuinely small. A Discogs pack with extractor, genre head, and the three candidate heads adds about 21.0 MiB. TensorFlow/Essentia likely dominate the full image, so this is not prohibitive, but it is not the same dependency or execution plan.

**Recommendation.** Keep only `mood_sad`, `mood_aggressive`, `mood_party`, `mood_electronic`, `voice_instrumental`, and optionally `tonal_atonal` in the MusiCNN extension pack. Move `timbre`, `approachability`, and `engagement` into the same opt-in Discogs-EffNet pack as `genre_discogs400`. The planner must make embedding-family dependencies explicit and must never substitute one embedding family for another.

### 🟡 Important — CONFIRMED current limitation: model downloads are digest-checked but not sufficiently bounded for larger/configurable packs

**Concrete failure scenario.** A built-in host redirects HTTPS to HTTP or an untrusted origin, stalls indefinitely, or sends a very large body. The current downloader follows five redirects without enforcing scheme or origin, has no explicit connect/read timeout, buffers the entire response in `response.body`, and only then writes it (`mood_probe/lib/mood_probe/model_store.rb:9-33`). SHA-256 prevents an incorrect artifact from being accepted, but it does not prevent memory/network DoS or redirect downgrade. If custom URLs become accepted, the same code becomes an SSRF primitive.

Current positive controls are strong: every built-in registry entry has a fixed SHA-256 and HTTPS URL (`mood_probe/lib/mood_probe/model_registry.rb:12-60`); downloaded bytes are checked before move; mismatch raises and the temporary is removed (`mood_probe/lib/mood_probe/model_store.rb:64-75`).

**Recommendation.**

- Gem ships a versioned manifest, not weights. Each entry should include descriptor/model ID, exact basename, SHA-256, exact byte length, canonical HTTPS URL, metadata URL, model/version, framework, algorithm enum, output node, expected input/output shape, dependencies, licence identifier, attribution text/URL, and model-pack membership.
- Built-in downloads: HTTPS only; allowlisted host; either reject redirects or permit only HTTPS redirects to an allowlisted host; explicit connect/read/total timeouts.
- Stream to a uniquely named temporary file in the target directory while hashing and enforcing the manifest byte limit. Do not buffer the response body.
- On length or digest mismatch: delete only the temporary file, preserve any previously verified model, raise a fatal configuration error, and do not fall back to unverified data.
- Reject symlink/path escapes before download and before model load. Atomically rename the verified file and use restrictive file permissions.
- Verify the complete selected pack during preflight before processing audio.
- Keep fetching out of normal job execution. Provision selected packs in a dedicated Docker build/deploy step or pre-deploy command, then run offline.

**Commit versus fetch recommendation.** Do not bundle weights in the public gem. Vibe Doctor may retain its existing 3.44 MiB of exact committed weights to avoid unrelated churn, but new packs should be fetched in a dedicated, digest-pinned build step or stored in a versioned artifact cache/Git LFS rather than expanding ordinary Git history. The final runtime image should contain only the selected verified packs. Committing exact upstream binaries gives the best network-independent reproducibility, but makes the application repository a redistributor with attribution/licence obligations and permanently grows Git history; verified build-time fetching avoids that history cost but adds an upstream availability dependency. A cache plus immutable manifest gives the best proportional trade-off.

Recommended operator packs:

- `core_musicnn`: current extractor and six outputs; default for Vibe Doctor.
- `extended_musicnn`: five extra mood/voice heads and optionally `tonal_atonal`; explicit opt-in, negligible size.
- `discogs_effnet`: extractor plus selected 1280/400-dimensional outputs; explicit opt-in due separate compute, ~20–21 MiB footprint, and storage implications.
- DSP/dynamics descriptors: no model pack unless the selected implementation itself requires weights (for example TempoCNN); audit such a model separately before adding it.

### 🟡 Important — CONFIRMED: the git dependency is content-pinned today, but branch-based resolution remains a mutable update path

**Concrete failure scenario.** A maintainer or compromised account moves `main`; the next `bundle update mood_probe` accepts that new tip without an immutable release decision. Conversely, a force-push that makes locked commit `5360f8f` unreachable can break a clean rebuild after GitHub garbage-collects it.

The current `Gemfile` uses anonymous public HTTPS and `branch: "main"` (`vibe-doctor/Gemfile:34`). `Gemfile.lock` records exact revision `5360f8fd...` (`vibe-doctor/Gemfile.lock:1-6`). Docker installs Git and runs `bundle install` in the build stage (`vibe-doctor/Dockerfile:41-55`).

**Assessment.**

- The lockfile revision is sufficient to prevent a moved/force-pushed branch from silently changing the gem during an ordinary frozen/deployment install. Git object identity and the locked SHA remain the requested content.
- A force-push cannot make different content resolve as that same SHA in the normal threat model; it can make the commit unavailable, causing a build failure.
- `bundle update mood_probe` intentionally re-resolves the mutable branch and is the update trust point.
- Anonymous HTTPS is appropriate for a public repository. Authentication would improve access control for a private source, not the integrity of public bytes; TLS plus the locked Git object supplies transport/content integrity. Availability and GitHub-account compromise remain.

**Recommendation.** For V2, publish signed/versioned gem releases and consume a fixed version from RubyGems, with MFA/trusted publishing and a reviewable release process. Until then, use an exact `ref:` in `Gemfile` rather than a branch declaration, retain the lockfile, and update the ref deliberately. Archive release source/artifacts so a rewritten branch cannot make deployment unrebuildable.

### 🟡 Important — PLAUSIBLE: embeddings can become an unintended data-export surface if persisted through existing generic resources

**Concrete failure scenario.** New MusiCNN/Discogs vectors are added to a generic serializer, admin resource, job log, or recommendation event and become available to API callers or unnecessarily rendered in HTML. High-dimensional audio representations are derived fingerprints of the user's media and collection; they are not equivalent to raw audio, but they enable similarity/profiling and should not be exported by default.

Current state:

- Siri/recommendation JSON returns album ID, title, artists, genres, and explanation, not mood vectors or embeddings (`vibe-doctor/app/controllers/recommendations_controller.rb:4-20`).
- The authenticated vibe-map JSON exposes the current six mood scalars (`vibe-doctor/app/models/albums/vibe_map_builder.rb:31-46`).
- Existing 1536-dimensional text embeddings are stored in fixed pgvector columns (`vibe-doctor/db/schema.rb:68-77`) and are visible through `EmbeddingResource` (`vibe-doctor/app/madmin/resources/embedding_resource.rb:1-12`).
- Madmin requires both an admin user and a persisted session (`vibe-doctor/app/controllers/madmin/application_controller.rb:1-15`).
- Current `mood_vectors` contain six scalars and JSON spread, not audio embeddings (`vibe-doctor/db/schema.rb:93-108`).

**Recommendation.**

- Store audio-native vectors in a dedicated, versioned table or explicitly named fixed-dimension columns; do not overload the existing 1536-dimensional text embedding columns. MusiCNN is 200-dimensional per patch before pooling, Discogs-EffNet metadata exposes a 1280-dimensional embedding, and `genre_discogs400` is a 400-class output.
- Persist only the pooled/derived representation the product needs, not unbounded per-patch series.
- Do not add vectors to Siri responses, public/application JSON, explanations, recommendation-event JSON, or logs. Log descriptor IDs, dimensions, model versions, and errors—not values.
- Keep admin display opt-in and preferably summarize dimensions/provenance rather than rendering full vectors in index pages.
- Include extractor/model version and pooling method so stale or incompatible embeddings can be invalidated safely.

## Hard architectural constraints

1. **Only descriptor IDs cross the Ruby/Python request boundary.** All paths, algorithms, output nodes, dimensions, provenance, dependencies, and model URLs resolve from independently validated trusted registries.
2. **Runtime registration is a full-trust operator extension, never untrusted data.** Default registration is declarative, local, bounded, and cannot inject Python/Ruby code, arbitrary URLs, paths, imports, or native algorithm names.
3. **Every model loaded by default is an exact verified artifact.** Immutable manifest, SHA-256 plus exact byte length, canonical path containment, bounded HTTPS download, and fatal mismatch.
4. **Every output is bounded and typed.** Stream-size caps, exact NDJSON cardinality, exact requested-ID set, recursive finite checks, type/dimension/item limits, and `allow_nan=False`.
5. **Model packs are explicit.** Core MusiCNN remains default; extended MusiCNN and Discogs-EffNet are separately selectable. `timbre`, `approachability`, and `engagement` belong to the Discogs pack.
6. **No new embedding exposure by default.** Separate versioned storage; no Siri/API/log serialization unless deliberately reviewed.
7. **Non-commercial licensing is visible and enforceable operationally.** The gem ships no weights, presents attribution/licence before fetch, and does not imply commercial permission.

## Evidence

### Repository state

- `vibe-doctor` HEAD: `0499d9cd38e7009eccbc6f75e50e93bd4800bc3e`
- `mood_probe` HEAD: `5360f8fd8609eae39edb5dfab8a07f6439a0b137`
- Both `git status --short` outputs were empty before report creation.
- No repository files were modified.

### Commands run

```text
git -C /Users/lukeolson/projects/vibe-doctor rev-parse HEAD
git -C /Users/lukeolson/projects/vibe-doctor status --short
git -C /Users/lukeolson/projects/gems/mood_probe rev-parse HEAD
git -C /Users/lukeolson/projects/gems/mood_probe status --short

git -C <repo> show HEAD:<file> | nl -ba
git -C <repo> grep -n <patterns> HEAD -- <paths>
git -C /Users/lukeolson/projects/vibe-doctor ls-tree -r -l HEAD tmp/essentia_models

curl -fsSL https://essentia.upf.edu/models/<model-directory>/
curl -fsSL https://essentia.upf.edu/models/<model>.json | jq ...
curl -fsSL -o <temporary-file> https://essentia.upf.edu/models/<model>.pb
wc -c <temporary-file>
shasum -a 256 <temporary-file>

ruby -rjson -e 'JSON.parse(%q({"v":NaN}))'
python3 -c '... json.dumps(...); json.dumps(..., allow_nan=False) ...'
```

Selected command outputs:

```text
Ruby: JSON::ParserError: unexpected token 'NaN}' at line 1 column 6
Python default: {"scalar": NaN, "vector": [1.0, NaN]}
Python allow_nan=False: ValueError: Out of range float values are not JSON compliant

genre_discogs400-discogs-effnet-1.pb:
bytes=2057977
sha256=3885ba078a35249af94b8e5e4247689afac40deca4401a4bc888daf5a579c01c
```

The current documented Brakeman/bundler-audit baseline was not rerun because this is a proposed-design review with no code diff, and the task explicitly identified the existing unrelated Bundler advisories as out of scope.

### Primary external sources fetched

- https://essentia.upf.edu/licensing_information.html
- https://essentia.upf.edu/models/LICENSE
- https://essentia.upf.edu/models/README.md
- https://essentia.upf.edu/models.html
- https://essentia.upf.edu/models/feature-extractors/musicnn/msd-musicnn-1.json
- https://essentia.upf.edu/models/feature-extractors/discogs-effnet/discogs-effnet-bs64-1.json
- https://essentia.upf.edu/models/classification-heads/genre_discogs400/genre_discogs400-discogs-effnet-1.json
- https://essentia.upf.edu/models/classification-heads/mood_sad/mood_sad-msd-musicnn-1.json
- https://essentia.upf.edu/models/classification-heads/mood_aggressive/mood_aggressive-msd-musicnn-1.json
- https://essentia.upf.edu/models/classification-heads/mood_party/mood_party-msd-musicnn-1.json
- https://essentia.upf.edu/models/classification-heads/mood_electronic/mood_electronic-msd-musicnn-1.json
- https://essentia.upf.edu/models/classification-heads/voice_instrumental/voice_instrumental-msd-musicnn-1.json
- https://essentia.upf.edu/models/classification-heads/tonal_atonal/tonal_atonal-msd-musicnn-1.json
- https://essentia.upf.edu/models/classification-heads/timbre/timbre-discogs-effnet-1.json
- https://essentia.upf.edu/models/classification-heads/approachability/approachability_2c-discogs-effnet-1.json
- https://essentia.upf.edu/models/classification-heads/engagement/engagement_2c-discogs-effnet-1.json

### Unverified / unresolved

- **UNVERIFIED legally:** MTG has not resolved the conflict between its BY-NC-SA model summary and BY-NC-ND licensing page/legal text. This report uses the more restrictive ND terms as the compliance floor; it is not legal advice.
- **UNVERIFIED provenance detail:** Discogs-4M training data is described by the official model metadata as unreleased. Its separate training-data rights and MTG/Discogs arrangement are not publicly established by the sources reviewed.
- **UNVERIFIED future design:** No generalized descriptor registry, custom-registration API, vector/series protocol, or audio-embedding persistence exists at the reviewed SHAs. Findings labeled PLAUSIBLE attach to the proposed design, not current exploitable endpoints.
