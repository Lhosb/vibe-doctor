# MOOD-SCALE Baseline Capture (Step 2)

Date: 2026-08-14

This baseline is captured **before any mood-metric behaviour change**, per sequence step 2 in principal.md.

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

## Query and catalog provenance

- Database used: `vibe_doctor_development`
- Row filter: `mood_vectors.mood_source LIKE 'essentia%'`
- Catalog rows used: 321
- Source split: `essentia_itunes=314`, `essentia_youtube=7`

This is a **development database baseline only**. Production representativeness is unverified.

## Baseline metrics

Computed using current Euclidean metric over six 0..1 heads and current normalization (`distance / sqrt(6)`).

- `REFERENCE_DISTANCE` baseline (median pairwise distance across fixed queries x catalog rows): **0.809199**
- Current mean mood term across fixed queries x catalog rows: **0.344698**
- Mood term min/max over that matrix: **0.066906 / 0.735105**

## SQL used

Saved in `/tmp/run_mood_baseline.sql` during execution and run via:

```bash
bundle exec rails runner "puts ActiveRecord::Base.connection.select_all(File.read('/tmp/run_mood_baseline.sql')).to_a"
```

Result payload:

```ruby
{"database_name" => "vibe_doctor_development", "catalog_row_count" => 321, "query_count" => 12, "reference_distance_p50" => 0.809199e0, "mean_mood_term" => 0.344698e0, "min_mood_term" => 0.66906e-1, "max_mood_term" => 0.735105e0}
```
