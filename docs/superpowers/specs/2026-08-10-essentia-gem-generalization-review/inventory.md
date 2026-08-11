# ESSENTIA-GEM-V2 — vibe-doctor consumer inventory

Read-only inventory of `vibe-doctor` at `0499d9cd38e7009eccbc6f75e50e93bd4800bc3e`.

## 1. MoodVector persistence and model contract

`MoodVector` belongs to one album and defines the app’s six-head contract as
`valence`, `arousal`, `danceability`, `mood_acoustic`, `mood_relaxed`, and
`mood_happy`; the model also defines the accepted sources as `essentia_itunes`,
`essentia_youtube`, and `llm_only` (`app/models/mood_vector.rb:2-9`).

The current table has these columns (`db/schema.rb:93-108`):

| Column | Type | Null/default |
|---|---|---|
| `album_id` | bigint | non-null |
| `valence` | float | non-null, `0.5` |
| `arousal` | float | non-null, `0.5` |
| `danceability` | float | non-null, `0.5` |
| `mood_acoustic` | float | non-null, `0.5` |
| `mood_relaxed` | float | non-null, `0.5` |
| `mood_happy` | float | non-null, `0.5` |
| `mood_source` | string | non-null, `"llm_only"` |
| `match_confidence` | float | non-null, `0.0` |
| `spread` | jsonb | non-null, `{}` |
| `created_at`, `updated_at` | datetime | non-null |

The database enforces one mood vector per album with a unique `album_id` index,
enforces the album foreign key, and constrains `mood_source` to the three known
values (`db/migrate/20260721214250_create_mood_vectors.rb:3-19`;
`db/schema.rb:106-107`). The database does **not** add range constraints for the
six floats, a range/shape constraint for `spread`, or a range constraint for
`match_confidence`; the migration’s only explicit check constraint is for
`mood_source` (`db/migrate/20260721214250_create_mood_vectors.rb:17-19`).

At the application layer, `mood_source` has an inclusion validation and every
head must be numeric in `0.0..1.0`; there is no model validation for
`match_confidence` or `spread` (`app/models/mood_vector.rb:8-9`).

`match_confidence` is not computed from the feature vectors. For iTunes it is
copied from the **first** matched preview, for YouTube it is the literal `1.0`,
and for fallback it is `0.0`
(`app/services/mood_grounding_service.rb:45-46,49-60,63-81`).

`spread` is stored as a JSONB head-to-float object. Each value is the population
standard deviation across surviving tracks for that head, rounded to ten
decimal places; a single surviving track gets `0.0`
(`app/services/mood_grounding_service.rb:140-155`). `EnrichAlbumJob` writes the
complete returned attribute hash with `mood_vector.update!`, so both
`match_confidence` and `spread` are persisted with the six means
(`app/jobs/enrich_album_job.rb:23-26`).

## 2. Consumer seam: MoodGroundingService

The sole production consumer constructs `MoodProbe::Extractor` with only
`models_dir`, defaulting `ESSENTIA_MODELS_DIR` to
`tmp/essentia_models` (`app/services/mood_grounding_service.rb:6-14`).
The resolved dependency is the Git `main` branch at revision
`5360f8fd8609eae39edb5dfab8a07f6439a0b137`
(`Gemfile:34`; `Gemfile.lock:1-6`).

For an iTunes preview, the service downloads bytes to a temporary file and
calls `@feature_extractor.analyze(dest_path).to_h`; for a YouTube clip it calls
`@feature_extractor.analyze(clip_path).to_h`
(`app/services/mood_grounding_service.rb:87-107`). In the resolved gem,
`Extractor#analyze` returns `result.features`, and `Features#to_h` returns a
duplicate of its internal head-value hash
(`/Users/lukeolson/.asdf/installs/ruby/4.0.1/lib/ruby/gems/4.0.0/bundler/gems/mood_probe-5360f8fd8609/lib/mood_probe/extractor.rb:26-30`;
`/Users/lukeolson/.asdf/installs/ruby/4.0.1/lib/ruby/gems/4.0.0/bundler/gems/mood_probe-5360f8fd8609/lib/mood_probe/features.rb:14-25`).

The gem’s current `Features::HEADS` is the same six symbols, and `Features`
rejects missing or extra keys before exposing the hash
(`/Users/lukeolson/.asdf/installs/ruby/4.0.1/lib/ruby/gems/4.0.0/bundler/gems/mood_probe-5360f8fd8609/lib/mood_probe/features.rb:3-5,29-35`).

The app assumes the payload is a flat, symbol-keyed map. Aggregation iterates
`MoodVector::MOOD_HEADS` and directly indexes every track payload with
`coords[head]`; there is no namespace, nested feature family, feature metadata,
or lookup adapter between the gem and the model
(`app/services/mood_grounding_service.rb:140-148`). The app also assumes every
returned value supports numeric summation, subtraction, exponentiation, square
root, and rounding (`app/services/mood_grounding_service.rb:144-154`).

The service tries iTunes first, then YouTube, then returns the fallback after
checking whether both sources showed a systematic extractor failure
(`app/services/mood_grounding_service.rb:24-40`). Track-level
`MoodProbe::TrackError` values are logged and skipped, while errors outside that
class are not rescued by the per-track methods
(`app/services/mood_grounding_service.rb:87-114`). Temporary iTunes files and
YouTube clip files are deleted in `ensure` paths
(`app/services/mood_grounding_service.rb:102-114`; `app/services/mood_grounding_service.rb:74-84`).

## 3. Per-track to per-album aggregation

The exact aggregation implementation is (`app/services/mood_grounding_service.rb:140-155`):

```ruby
def aggregate(track_coords)
  means = {}
  spreads = {}
  MoodVector::MOOD_HEADS.each do |head|
    values = track_coords.map { |coords| coords[head] }
    means[head] = (values.sum / values.size.to_f).round(10)
    spreads[head] = values.size > 1 ? population_stddev(values) : 0.0
  end
  means.merge(spread: spreads)
end

def population_stddev(values)
  mean = values.sum / values.size.to_f
  variance = values.sum { |value| (value - mean)**2 } / values.size.to_f
  Math.sqrt(variance).round(10)
end
```

Thus each album head is the unweighted arithmetic mean of surviving tracks,
rounded to ten decimal places, and spread is the unweighted population
standard deviation divided by `N`, also rounded to ten decimal places
(`app/services/mood_grounding_service.rb:140-155`). There is no per-track
confidence weighting in either calculation (`app/services/mood_grounding_service.rb:140-155`).
The source-level confidence is merged only after aggregation: first-preview
confidence for iTunes and `1.0` for YouTube
(`app/services/mood_grounding_service.rb:49-60,63-81`).

The grounding spec pins a two-track valence mean of `0.5`, population spread of
`0.3`, and one `on_matched` callback; it also pins all-zero spread for one track
(`spec/services/mood_grounding_service_spec.rb:25-49`).

## 4. EnrichAlbumJob orchestration

`EnrichAlbumJob` runs on the `default` queue (`app/jobs/enrich_album_job.rb:1-2`).
Its successful order is:

1. Construct/receive the extractor and call `verify!` before matching
   (`app/jobs/enrich_album_job.rb:4-11`).
2. Move the album to `matching_audio`
   (`app/jobs/enrich_album_job.rb:13`; `app/models/album.rb:29-31`).
3. Ground audio; the first match callback moves the album to
   `extracting_features`, while an unmatched fallback is moved there after
   `ground` returns (`app/jobs/enrich_album_job.rb:15-24`).
4. Build or reuse the one `MoodVector` and update it with the returned flat
   attributes (`app/jobs/enrich_album_job.rb:25-26`).
5. Generate and upsert the `VibeCard`, saving an empty/default card when
   generation returns nil (`app/jobs/enrich_album_job.rb:28-38`).
6. Generate four embeddings, build or reuse the `Embedding`, and update it
   (`app/jobs/enrich_album_job.rb:40-42`).
7. Transition the album to `grounded` (`app/jobs/enrich_album_job.rb:44`;
   `app/models/album.rb:37-39`).

Any `StandardError` is logged, the job attempts to transition the album to
`failed`, an invalid failure transition is suppressed, and the original error
is re-raised (`app/jobs/enrich_album_job.rb:45-52`). The job class declares no
`retry_on` or `discard_on`; `ApplicationJob` contains only commented examples,
so any retry behavior is the queue adapter’s/default Active Job behavior rather
than an app-declared EnrichAlbumJob policy
(`app/jobs/application_job.rb:1-7`; `app/jobs/enrich_album_job.rb:1-53`).

The job spec verifies the complete state flow and persistence of mood source,
spread, vibe card, and embedding; it also verifies the `llm_only` path,
failure-state transition/re-raise, and extractor preflight before HTTP
(`spec/jobs/enrich_album_job_spec.rb:36-52,68-78,80-113`).

## 5. Cache invalidation and backfill

### Current `main`: no versioned invalidation mechanism found

The current album model’s automatic backfill scope is status-only:
`pending` or `failed`; it does not compare a version or timestamp
(`app/models/album.rb:22-24`). `enrichment:backfill` synchronously sends exactly
that scope through the job (`lib/tasks/enrichment.rake:8-12,29-48`), and its
spec verifies that a grounded album is skipped
(`spec/tasks/enrichment_rake_spec.rb:50-61`).

The current force-invalidation mechanism is `Album#reset_enrichment!`, which
sets only `enrichment_status: "pending"` (`app/models/album.rb:45-50`).
`enrichment:reground_all` preflights Essentia, loads **all albums**, resets each
one to pending, and synchronously re-enriches them
(`lib/tasks/enrichment.rake:14-26`). This operates at whole-album granularity:
the job subsequently overwrites/reuses the album’s `MoodVector`, `VibeCard`,
and four-facet `Embedding` records (`app/jobs/enrich_album_job.rb:23-42`).

The schema contains an indexed nullable `albums.last_enriched_at`
(`db/schema.rb:30-44`), but the current `CreateAlbums` migration does not create
it (`db/migrate/20260721214207_create_albums.rb:3-16`), and current searches of
`app/`, `lib/`, `db/`, `config/`, and `spec/` found no application reference to
`last_enriched_at`, `ENRICHMENT_VERSION`, `enrichment_version`,
`CACHE_VERSION`, or `cache_version` beyond the two schema lines. Therefore,
`main` has neither a version constant/column nor code that stamps or compares
the timestamp.

The apparent source of the brief’s premise is a separate, unmerged branch:
commit `72bb8fc` added `last_enriched_at` plus a time-staleness rake task, and
commit `f59f159` stamped successful jobs, but `git branch --contains 72bb8fc`
reports only `feat/vibe-doctor-rollout-hardening`; `git merge-base
--is-ancestor 72bb8fc HEAD` exits 1. This historical mechanism was time-based
(`nil` or older than 30 days), not extractor/version keyed
(`72bb8fc:db/migrate/20260723090000_add_last_enriched_at_to_albums.rb:1-6`;
`f59f159:app/jobs/enrich_album_job.rb:35-36`).

### Backfill behavior available today

- Newly created albums are enqueued for `EnrichAlbumJob` by the collection sync
  only when the album record was newly created
  (`app/jobs/sync_discogs_collection_job.rb:35`).
- Ordinary `enrichment:backfill` handles pending and failed albums only
  (`app/models/album.rb:24`; `lib/tasks/enrichment.rake:9-12`).
- `enrichment:reground_all` is the only current path that deliberately
  invalidates already-grounded albums, and it does so for every album
  (`lib/tasks/enrichment.rake:14-26`).
- The batch runner continues after ordinary per-album exceptions, but re-raises
  `MoodProbe::FatalError`; it also aborts after five consecutive `llm_only`
  results (`lib/tasks/enrichment.rake:35-74`).

## 6. `llm_only` fallback

Fallback is chosen only after iTunes and YouTube return no usable aggregate and
the service does not have dual-source systematic failure evidence
(`app/services/mood_grounding_service.rb:33-40,133-138`). It produces every
head at `0.5`, `mood_source: "llm_only"`, `match_confidence: 0.0`, and an empty
`spread` object (`app/services/mood_grounding_service.rb:45-46`).

`EnrichAlbumJob` still moves an unmatched album to `extracting_features`,
persists that fallback `MoodVector`, generates/saves the vibe card and text
embeddings, and finally marks the album grounded
(`app/jobs/enrich_album_job.rb:23-44`). The job spec explicitly verifies a
grounded album whose persisted mood source is `llm_only`
(`spec/jobs/enrich_album_job_spec.rb:68-78`), and the service spec verifies the
fallback confidence, empty spread, and neutral valence
(`spec/services/mood_grounding_service_spec.rb:65-76`).

## 7. Existing embeddings and pgvector columns

The PostgreSQL `vector` extension is enabled
(`db/migrate/20260721213908_enable_vector_extension.rb:1-4`;
`db/schema.rb:13-16`).

`AlbumEmbeddingService` does not compute an audio/MusiCNN embedding. It sends
four constructed text strings in one OpenAI `text-embedding-3-small` request
and returns vectors keyed as `sonic`, `emotional`, `situational`, and `era`
(`app/services/album_embedding_service.rb:1-20`). Those texts are composed from
album title/artists/year/genres/styles, the generated vibe card, and a rendered
description of the persisted mood vector
(`app/services/album_embedding_service.rb:24-57`).

`EnrichAlbumJob` persists the returned vectors into the album’s one
`Embedding` row (`app/jobs/enrich_album_job.rb:40-42`). The table has four
nullable `vector(1536)` columns—`sonic`, `emotional`, `situational`, and
`era`—and a unique album index (`db/schema.rb:68-77`;
`db/migrate/20260721214351_create_embeddings.rb:3-10`). The model enables
nearest-neighbor behavior for all four columns
(`app/models/embedding.rb:1-7`).

The other current pgvector column is
`query_understanding_caches.embedding`, a non-null `vector(1536)` associated
with cached query text and its digest/expiry
(`db/schema.rb:110-125`;
`db/migrate/20260722154648_create_query_understanding_caches.rb:3-20`).
No current schema column stores a raw audio or MusiCNN embedding
(`db/schema.rb:68-77,93-125`).

The embedding specs pin the four-facet order and the OpenAI model/input
construction, including fallback to era text for blank emotional/situational
facets (`spec/services/album_embedding_service_spec.rb:25-54`), and verify a
stored 1536-dimensional facet vector round-trips
(`spec/models/embedding_spec.rb:11-17`).

## 8. Golden, parity, and payload-shape coverage

`spec/integration/essentia_extract_golden_spec.rb` is tagged `:essentia`;
RSpec excludes that tag unless `ESSENTIA_SPECS=1`
(`spec/integration/essentia_extract_golden_spec.rb:15`;
`spec/spec_helper.rb:16-17`). It defines the six expected string keys, runs the
real extractor for four audio fixtures, asserts both actual and golden key
sets, then compares every float with a `1e-4` relative tolerance and `1e-10`
absolute floor; it separately requires undecodable audio to raise
`MoodProbe::UnreadableAudioError`
(`spec/integration/essentia_extract_golden_spec.rb:20-25,30-79`).

`spec/support/phase3_parity.rb` is an executable support harness rather than an
RSpec example. For the four decodable fixtures it runs the deleted app-owned
Python script and the gem extractor and aborts unless the two string-keyed
hashes are exactly equal (`spec/support/phase3_parity.rb:1-8,18-39`).

`spec/services/mood_grounding_service_spec.rb` constructs real
`MoodProbe::Features` objects around the six-symbol hash, so it pins the
consumer input object and exercises the resulting flat map
(`spec/services/mood_grounding_service_spec.rb:7-18`). It pins multi-track
mean/spread, single-track spread, source/confidence selection, fallback shape,
track-error skipping, and fatal-error propagation
(`spec/services/mood_grounding_service_spec.rb:25-76,78-204`).

There is **no direct assertion** in the app suite of
`MoodVector::MOOD_HEADS == MoodProbe::Features::HEADS`: the only
`Features::HEADS` definition is in the gem, while app-spec searches find
`MOOD_HEADS` only in the golden spec and rake specs. The golden test provides
an indirect runtime cross-check by comparing `extractor.analyze(...).to_h`
keys—the gem’s `Features` output—to its own duplicated six-string constant
(`spec/integration/essentia_extract_golden_spec.rb:20,37-42`;
`/Users/lukeolson/.asdf/installs/ruby/4.0.1/lib/ruby/gems/4.0.0/bundler/gems/mood_probe-5360f8fd8609/lib/mood_probe/features.rb:3,23-25`).
It does not reference `MoodVector::MOOD_HEADS`
(`spec/integration/essentia_extract_golden_spec.rb:1-81`).

## 9. Mood-vector migration history

On current `main`, the only migration that creates or changes
`mood_vectors` is `20260721214250_create_mood_vectors.rb`; it created the six
float columns, source, confidence, spread JSONB, timestamps, unique album
reference/foreign key, and source check in one migration
(`db/migrate/20260721214250_create_mood_vectors.rb:1-20`). `git log --all
-G'mood_vectors' -- db/migrate` returns only commit `0cd3dee`, which introduced
that migration. No later migration currently evolves the table.

The related persistence migrations are:

- `20260721213908_enable_vector_extension.rb`, enabling pgvector
  (`db/migrate/20260721213908_enable_vector_extension.rb:1-4`).
- `20260721214207_create_albums.rb`, creating the owning album and enrichment
  status (`db/migrate/20260721214207_create_albums.rb:1-16`).
- `20260721214250_create_mood_vectors.rb`, creating the current mood-vector
  table (`db/migrate/20260721214250_create_mood_vectors.rb:1-20`).
- `20260721214351_create_embeddings.rb`, creating the four album text-vector
  columns (`db/migrate/20260721214351_create_embeddings.rb:1-13`).
- `20260722154648_create_query_understanding_caches.rb`, creating the separate
  query embedding and six query mood floats
  (`db/migrate/20260722154648_create_query_understanding_caches.rb:1-22`).

The checked-in schema contains `albums.last_enriched_at` even though its
migration is absent from `main` (`db/schema.rb:35,43`;
`db/migrate/20260721214207_create_albums.rb:3-16`). That is schema/migration
drift, not a functioning current invalidation mechanism.

## Observations (separate from current-state facts)

1. The requirement brief’s statement that a versioned cache invalidation
   mechanism already exists does not match current `main`; the only current
   invalidation is the all-album status reset in `reground_all`
   (`app/models/album.rb:45-50`; `lib/tasks/enrichment.rake:14-26`).
2. The current consumer boundary is narrower than the gem’s proposed future
   surface: vibe-doctor immediately converts `Features` to a flat hash and
   discards any possibility of carrying feature-family metadata or an audio
   embedding through aggregation (`app/services/mood_grounding_service.rb:92-93,106-107,140-148`).
3. The app already has pgvector persistence, but all album vectors are OpenAI
   text embeddings rather than audio embeddings
   (`app/services/album_embedding_service.rb:1-20`; `db/schema.rb:68-77`).

## Evidence

### Revision and repository cleanliness

Command:

```text
git -C /Users/lukeolson/projects/vibe-doctor rev-parse HEAD
```

Output:

```text
0499d9cd38e7009eccbc6f75e50e93bd4800bc3e
```

Final cleanliness command:

```text
git -C "/Users/lukeolson/projects/vibe-doctor" status --porcelain
```

Output:

```text
```

### Commands run

```text
git -C /Users/lukeolson/projects/vibe-doctor rev-parse HEAD
git -C /Users/lukeolson/projects/vibe-doctor status --porcelain
git -C /Users/lukeolson/projects/vibe-doctor log --oneline --decorate -15
git -C /Users/lukeolson/projects/vibe-doctor log --all -S'last_enriched_at' --oneline -- db app lib spec
git -C /Users/lukeolson/projects/vibe-doctor log --all -G'ENRICHMENT_VERSION|enrichment_version|cache_version' --oneline -- app lib db spec
git -C /Users/lukeolson/projects/vibe-doctor log --all -G'mood_vectors' --oneline -- db/migrate
git -C /Users/lukeolson/projects/vibe-doctor branch --contains 72bb8fc
git -C /Users/lukeolson/projects/vibe-doctor merge-base --is-ancestor 72bb8fc HEAD
find /Users/lukeolson/projects/vibe-doctor/db/migrate -maxdepth 1 -type f -print | sort
rg 'last_enriched_at|ENRICHMENT_VERSION|enrichment_version|CACHE_VERSION|cache_version' app lib db config spec
rg 'MoodProbe::Features::HEADS|Features::HEADS|MOOD_HEADS' spec
rg 'EnrichAlbumJob|enrichment:backfill|reground_all' .
nl -ba <each cited implementation, migration, schema, spec, and resolved-gem file>
```

### Confirmed absences

- Searched current `app/`, `lib/`, `db/`, `config/`, and `spec/` for
  `last_enriched_at`, `ENRICHMENT_VERSION`, `enrichment_version`,
  `CACHE_VERSION`, and `cache_version`. Only `db/schema.rb:35,43` matched;
  there is no current stamping, comparison, or version mechanism.
- Searched current specs for `MoodProbe::Features::HEADS` and
  `Features::HEADS`. No direct app/gem constant equality assertion exists;
  the relevant app key assertions are
  `spec/integration/essentia_extract_golden_spec.rb:41-42`.
- Listed and history-searched migrations affecting `mood_vectors`. Only
  `db/migrate/20260721214250_create_mood_vectors.rb:1-20` exists on current
  `main`; no subsequent mood-vector persistence migration was found.
- Inspected current pgvector schema regions. No audio/MusiCNN embedding column
  exists; current vectors are the four album facet columns and one query-cache
  column (`db/schema.rb:68-77,110-125`).

