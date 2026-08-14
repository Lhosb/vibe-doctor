# Measurement: realized per-head spread in mood_vectors
Measured by Baton (Team Manager), 2026-08-14, read-only, against the LOCAL DEV database
vibe_doctor_development. Not production. n = 321 rows where mood_source LIKE 'essentia%'
(essentia_itunes 314, essentia_youtube 7). llm_only rows (1) excluded.

## Query used

psql -d vibe_doctor_development -c "
select h.head, round(h.mn::numeric,4) min, round(h.mx::numeric,4) max,
       round((h.mx-h.mn)::numeric,4) span, round(h.sd::numeric,4) stddev
from ( select 'valence' as head, min(valence) mn, max(valence) mx, stddev_pop(valence) sd
       from mood_vectors where mood_source like 'essentia%'
       union all ... (one arm per head) ) h order by h.sd desc;"

## Result

head            min      max      span     stddev   variance   share of distance
danceability    0.0011   1.0000   0.9989   0.3348   0.11209    28.2%
mood_acoustic   0.0000   0.9991   0.9991   0.3208   0.10291    25.9%
mood_relaxed    0.0004   0.9999   0.9996   0.3136   0.09835    24.8%
mood_happy      0.0041   0.9904   0.9863   0.2690   0.07236    18.2%
arousal         0.2747   0.7079   0.4332   0.0870   0.00757     1.9%
valence         0.3438   0.6739   0.3301   0.0592   0.00350     0.9%
                                                    total 0.39678

The four musicnn heads carry 97.2% of mood distance. The two emomusic heads carry 2.8%.
danceability outweighs valence by 32x on variance.

## Why

MoodVector#distance_to is unweighted Euclidean, so each head's influence goes as its VARIANCE,
not its stddev. EssentiaMapper#rescale_emomusic divides by the DECLARED emomusic range (1..9,
EMOMUSIC_RANGE), but the REALIZED range is far narrower. Inverting the rescale, (v*8)+1:
  valence realized  3.75 .. 6.39   out of declared 1..9
  arousal realized  3.20 .. 6.66   out of declared 1..9
musicnn heads arrive already spanning nearly the full 0..1. So dividing emomusic by the full
declared band compresses those two axes into near-irrelevance. Nobody chose this weighting.

## Two caveats that MUST survive into the design

1. ZERO rows sit at exactly 0.0 or 1.0, but this does NOT prove clamping never fires.
   mood_vectors stores album MEANS. Clamping happens PER TRACK inside EssentiaMapper#call,
   and MoodGroundingService#aggregate averages a saturated track with unsaturated ones.
   Per-track descriptor values are NEVER PERSISTED. This dataset is structurally incapable
   of observing per-track saturation. Evidence clamping is not pervasive; not evidence it
   never happens.
2. Dev database. Representativeness vs production is UNVERIFIED.
