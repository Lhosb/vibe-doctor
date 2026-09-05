# MOOD-SCALE Baseline Capture (Step 2)

> ## WITHDRAWN DESIGN CONTEXT (2026-08-14)
>
> This file preserves measurements from the withdrawn CatalogueScale design. References below to
> `CatalogueScale`, standardized z-space, and `REFERENCE_DISTANCE` are historical evidence, not
> current implementation guidance. The replacement is Option E in
> `docs/superpowers/specs/2026-08-14-mood-scale/principal-optionE.md`; step 4 removed the
> CatalogueScale class and its legacy metric API.

Date: 2026-08-14

This baseline is captured **before any mood-metric behaviour change**, per sequence step 2 in principal.md.

> **Population label correction (2026-08-15):**
> The 321 rows in this baseline are **one user's personal collection**, not a catalogue sample.
> In this dev environment there are 5 users, only 1 has a collection, that collection contains all
> 321 grounded albums, and zero grounded albums exist outside it.
>
> The 97.21%/2.79% influence split and 31.9x variance ratio cited in related measurement material
> are **n=1 figures** and **MUST NOT** be quoted as population facts.

## Option E step 1 addendum (2026-08-15)

Committed fixture files for permanent gates now live at:

- `spec/fixtures/mood_scale/catalogue_snapshot.json` (SHA-256: `34257e1c89abefbbbdaa4c8de0ab6dc37a21f02ada09bc022bbbf3a4124b6428`)
- `spec/fixtures/mood_scale/queries.json` (SHA-256: `f686686ebb75b2c9ea78673f824e9ee705f9de3a4393ce1fc5cf21684353b5f1`)

Independent named-column anchors from the original database measurement:

- `mood_happy` population standard deviation: `0.268967`
- `mood_relaxed` population standard deviation: `0.313610`
- query `q02` `mood_happy`: `0.30`
- query `q02` `mood_relaxed`: `0.60`

These anchors and the named query table below detect a fixture regenerated with the two values
assigned to the wrong keys. They are separate from the fixture SHA, which only detects an
unacknowledged byte change.

Step-4/G7 pinned baseline value (for dispersion-ratio calibration): `sd_old = 0.095101457`.

Fixture-generating command (one-user collection corpus):

```bash
bundle exec rails runner "require 'json'; rows=MoodVector.joins(:album).where(\"mood_source LIKE ?\",'essentia%').order('albums.id').pluck(:valence,:arousal,:danceability,:mood_acoustic,:mood_happy,:mood_relaxed).map{|v,a,d,ac,h,r|{'valence'=>v,'arousal'=>a,'danceability'=>d,'mood_acoustic'=>ac,'mood_happy'=>h,'mood_relaxed'=>r}}; fixture={'_provenance'=>{'dataset_label'=>'one_user_personal_collection','notes'=>'Development fixture captured from one user collection; not a catalogue sample.','database'=>'vibe_doctor_development','users_in_development'=>5,'users_with_collection'=>1,'grounded_albums_in_collection'=>321,'grounded_albums_outside_collection'=>0,'row_filter'=>\"mood_vectors.mood_source LIKE 'essentia%'\",'order_by'=>'albums.id ASC','captured_on'=>'2026-08-15'},'rows'=>rows}; File.write('spec/fixtures/mood_scale/catalogue_snapshot.json',JSON.pretty_generate(fixture)); queries=[{'id'=>'q01','valence'=>0.50,'arousal'=>0.50,'danceability'=>0.50,'mood_acoustic'=>0.50,'mood_happy'=>0.50,'mood_relaxed'=>0.50},{'id'=>'q02','valence'=>0.20,'arousal'=>0.80,'danceability'=>0.40,'mood_acoustic'=>0.70,'mood_happy'=>0.30,'mood_relaxed'=>0.60},{'id'=>'q03','valence'=>0.80,'arousal'=>0.20,'danceability'=>0.60,'mood_acoustic'=>0.30,'mood_happy'=>0.70,'mood_relaxed'=>0.40},{'id'=>'q04','valence'=>0.10,'arousal'=>0.90,'danceability'=>0.90,'mood_acoustic'=>0.20,'mood_happy'=>0.85,'mood_relaxed'=>0.15},{'id'=>'q05','valence'=>0.90,'arousal'=>0.10,'danceability'=>0.10,'mood_acoustic'=>0.80,'mood_happy'=>0.15,'mood_relaxed'=>0.85},{'id'=>'q06','valence'=>0.35,'arousal'=>0.65,'danceability'=>0.25,'mood_acoustic'=>0.75,'mood_happy'=>0.45,'mood_relaxed'=>0.55},{'id'=>'q07','valence'=>0.65,'arousal'=>0.35,'danceability'=>0.75,'mood_acoustic'=>0.25,'mood_happy'=>0.55,'mood_relaxed'=>0.45},{'id'=>'q08','valence'=>0.15,'arousal'=>0.40,'danceability'=>0.85,'mood_acoustic'=>0.60,'mood_happy'=>0.20,'mood_relaxed'=>0.30},{'id'=>'q09','valence'=>0.85,'arousal'=>0.60,'danceability'=>0.15,'mood_acoustic'=>0.40,'mood_happy'=>0.80,'mood_relaxed'=>0.70},{'id'=>'q10','valence'=>0.30,'arousal'=>0.30,'danceability'=>0.70,'mood_acoustic'=>0.70,'mood_happy'=>0.30,'mood_relaxed'=>0.70},{'id'=>'q11','valence'=>0.70,'arousal'=>0.70,'danceability'=>0.30,'mood_acoustic'=>0.30,'mood_happy'=>0.70,'mood_relaxed'=>0.30},{'id'=>'q12','valence'=>0.05,'arousal'=>0.50,'danceability'=>0.95,'mood_acoustic'=>0.50,'mood_happy'=>0.05,'mood_relaxed'=>0.95}]; File.write('spec/fixtures/mood_scale/queries.json',JSON.pretty_generate(queries));"
```

## Fixed query set

12 fixed query vectors in 0..1 space:

| id | valence | arousal | danceability | mood_acoustic | mood_happy | mood_relaxed |
|---|---:|---:|---:|---:|---:|---:|
| q01 | 0.50 | 0.50 | 0.50 | 0.50 | 0.50 | 0.50 |
| q02 | 0.20 | 0.80 | 0.40 | 0.70 | 0.30 | 0.60 |
| q03 | 0.80 | 0.20 | 0.60 | 0.30 | 0.70 | 0.40 |
| q04 | 0.10 | 0.90 | 0.90 | 0.20 | 0.85 | 0.15 |
| q05 | 0.90 | 0.10 | 0.10 | 0.80 | 0.15 | 0.85 |
| q06 | 0.35 | 0.65 | 0.25 | 0.75 | 0.45 | 0.55 |
| q07 | 0.65 | 0.35 | 0.75 | 0.25 | 0.55 | 0.45 |
| q08 | 0.15 | 0.40 | 0.85 | 0.60 | 0.20 | 0.30 |
| q09 | 0.85 | 0.60 | 0.15 | 0.40 | 0.80 | 0.70 |
| q10 | 0.30 | 0.30 | 0.70 | 0.70 | 0.30 | 0.70 |
| q11 | 0.70 | 0.70 | 0.30 | 0.30 | 0.70 | 0.30 |
| q12 | 0.05 | 0.50 | 0.95 | 0.50 | 0.05 | 0.95 |

## Query and collection provenance

- Database used: `vibe_doctor_development`
- Row filter: `mood_vectors.mood_source LIKE 'essentia%'`
- Collection rows used: 321
- Source split: `essentia_itunes=314`, `essentia_youtube=7`

This is a **development database baseline only**. Production representativeness is unverified.

## Baseline metrics

### Current-space recommendation baseline (retained only as §4.3 acceptance input)

Computed using the current Euclidean metric over six stored 0..1 heads and current normalization (`distance / sqrt(6)`), across the fixed query set x grounded collection matrix.

- Current-space query-matrix median distance baseline (round-1 mistaken `REFERENCE_DISTANCE`, retained only as §4.3 acceptance input): **0.809199**
- Current mean mood term across fixed queries x collection rows: **0.344698**
- Mood term min/max over that matrix: **0.066906 / 0.735105**

### Collection pairwise reference-distance metrics (for §4.2)

Computed over grounded collection **pairwise rows** (`mood_source LIKE 'essentia%'`, n=321):

- Pairwise median distance in stored 0..1 space (`d_01`): **0.785407**
- Pairwise median distance in standardized z-space (`d_z`): **3.021725**

As part of the withdrawn design, `MoodVectors::CatalogueScale::REFERENCE_DISTANCE` was pinned to
`d_z` (**3.021725**) because principal.md §4.2 defined `REFERENCE_DISTANCE` in standardized
recommendation space, not stored 0..1 display space. The class no longer exists; this value is
retained only as a record of that design.

## SQL used

Saved in `/tmp/run_mood_baseline.sql` during execution and run via:

```bash
bundle exec rails runner "puts ActiveRecord::Base.connection.select_all(File.read('/tmp/run_mood_baseline.sql')).to_a"
```

Result payload (current-space query baseline):

```ruby
{"database_name" => "vibe_doctor_development", "catalog_row_count" => 321, "query_count" => 12, "reference_distance_p50" => 0.809199e0, "mean_mood_term" => 0.344698e0, "min_mood_term" => 0.66906e-1, "max_mood_term" => 0.735105e0}
```

Result payload (collection pairwise 0..1 vs z-space):

```ruby
{"database_name" => "vibe_doctor_development", "n" => 321, "reference_distance_01_p50" => 0.7854067049935953, "reference_distance_z_p50" => 3.0217250259286104}
```
