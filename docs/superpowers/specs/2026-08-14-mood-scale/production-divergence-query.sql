-- MOOD-SCALE: per-user vs global head-distribution divergence
-- READ-ONLY. Aggregates only: no PII, no titles, no track data, no row-level output.
-- Purpose: decide whether frozen GLOBAL mu/sigma can legitimately standardize
-- PER-USER rankings, given ranking always happens inside one user's collection
-- (pipeline.rb:53-55 -> candidate_retrieval.rb:34).

-- ============================================================
-- 1. GLOBAL baseline over all grounded rows
-- ============================================================
SELECT 'GLOBAL' AS scope,
       count(*)                              AS grounded_albums,
       round(avg(valence)::numeric,        6) AS mu_valence,
       round(stddev_pop(valence)::numeric, 6) AS sd_valence,
       round(avg(arousal)::numeric,        6) AS mu_arousal,
       round(stddev_pop(arousal)::numeric, 6) AS sd_arousal,
       round(avg(danceability)::numeric,        6) AS mu_dance,
       round(stddev_pop(danceability)::numeric, 6) AS sd_dance,
       round(avg(mood_acoustic)::numeric,        6) AS mu_acoustic,
       round(stddev_pop(mood_acoustic)::numeric, 6) AS sd_acoustic,
       round(avg(mood_happy)::numeric,        6) AS mu_happy,
       round(stddev_pop(mood_happy)::numeric, 6) AS sd_happy,
       round(avg(mood_relaxed)::numeric,        6) AS mu_relaxed,
       round(stddev_pop(mood_relaxed)::numeric, 6) AS sd_relaxed
FROM mood_vectors
WHERE mood_source LIKE 'essentia%';

-- ============================================================
-- 2. PER-USER, same statistics, over each user's own collection
--    This is the population that ranking actually runs against.
-- ============================================================
SELECT ci.user_id::text AS scope,
       count(*)                              AS grounded_albums,
       round(avg(mv.valence)::numeric,        6) AS mu_valence,
       round(stddev_pop(mv.valence)::numeric, 6) AS sd_valence,
       round(avg(mv.arousal)::numeric,        6) AS mu_arousal,
       round(stddev_pop(mv.arousal)::numeric, 6) AS sd_arousal,
       round(avg(mv.danceability)::numeric,        6) AS mu_dance,
       round(stddev_pop(mv.danceability)::numeric, 6) AS sd_dance,
       round(avg(mv.mood_acoustic)::numeric,        6) AS mu_acoustic,
       round(stddev_pop(mv.mood_acoustic)::numeric, 6) AS sd_acoustic,
       round(avg(mv.mood_happy)::numeric,        6) AS mu_happy,
       round(stddev_pop(mv.mood_happy)::numeric, 6) AS sd_happy,
       round(avg(mv.mood_relaxed)::numeric,        6) AS mu_relaxed,
       round(stddev_pop(mv.mood_relaxed)::numeric, 6) AS sd_relaxed
FROM collection_items ci
JOIN mood_vectors mv ON mv.album_id = ci.album_id
WHERE mv.mood_source LIKE 'essentia%'
GROUP BY ci.user_id
ORDER BY grounded_albums DESC;

-- ============================================================
-- 3. OVERLAP — are the collections actually distinct populations,
--    or largely the same albums? Near-total overlap would mean
--    the per-user numbers above are not independent evidence.
-- ============================================================
SELECT (SELECT count(DISTINCT user_id) FROM collection_items)        AS users_with_collections,
       (SELECT count(*) FROM mood_vectors
          WHERE mood_source LIKE 'essentia%')                         AS grounded_total,
       (SELECT count(*) FROM mood_vectors mv
          WHERE mv.mood_source LIKE 'essentia%'
            AND NOT EXISTS (SELECT 1 FROM collection_items ci
                            WHERE ci.album_id = mv.album_id))         AS grounded_in_no_collection,
       (SELECT count(*) FROM (
          SELECT album_id FROM collection_items
          GROUP BY album_id HAVING count(DISTINCT user_id) > 1) t)    AS albums_shared_by_2plus_users;
