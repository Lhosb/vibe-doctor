module MoodVectors
  class CatalogueScale
    VERSION = "2026-08-14-v1".freeze

    # Measured on vibe_doctor_development, 2026-08-14.
    # Row filter: mood_source LIKE 'essentia%'. n = 321 (essentia_itunes=314, essentia_youtube=7).
    # NOTE: this is not a production-representative sample.
    SAMPLE_SIZE = 321

    # Per-head mean (mu) in stored 0..1 space.
    MU = {
      valence: 0.5048,
      arousal: 0.4898,
      danceability: 0.3860,
      mood_acoustic: 0.6512,
      mood_happy: 0.5043,
      mood_relaxed: 0.6516
    }.freeze

    # Per-head population standard deviation (sigma) in stored 0..1 space.
    SIGMA = {
      valence: 0.0592,
      arousal: 0.0870,
      danceability: 0.3348,
      mood_acoustic: 0.3208,
      mood_happy: 0.2690,
      mood_relaxed: 0.3136
    }.freeze

    # Baseline median pairwise Euclidean distance from the fixed query set captured in
    # docs/superpowers/specs/2026-08-14-mood-scale/baseline.md, BEFORE metric changes.
    REFERENCE_DISTANCE = 0.809199

    # Finding B limitation (principal.md §3.5): the six heads are not six independent dimensions.
    # In the measured catalog, corr(arousal, mood_relaxed) = -0.9014. Per-head standardization
    # therefore still weights the energy/relaxation axis more than an independent axis would.
    # This limitation is declared, not solved, in this ticket.
    FINDING_B_CORRELATION = {
      arousal_vs_mood_relaxed: -0.9014
    }.freeze

    # Drift check query for reviewer/operator runs against a grounded catalog dataset.
    # Expected usage: run against development/production-like data and compare to MU/SIGMA using
    # DRIFT_TOLERANCE_RELATIVE. Not executed in test suite because tests run against an empty DB.
    DRIFT_CHECK_SQL = <<~SQL.freeze
      WITH rows AS (
        SELECT valence, arousal, danceability, mood_acoustic, mood_happy, mood_relaxed
        FROM mood_vectors
        WHERE mood_source LIKE 'essentia%'
      )
      SELECT
        count(*) AS n,
        avg(valence) AS valence_mu,
        stddev_pop(valence) AS valence_sigma,
        avg(arousal) AS arousal_mu,
        stddev_pop(arousal) AS arousal_sigma,
        avg(danceability) AS danceability_mu,
        stddev_pop(danceability) AS danceability_sigma,
        avg(mood_acoustic) AS mood_acoustic_mu,
        stddev_pop(mood_acoustic) AS mood_acoustic_sigma,
        avg(mood_happy) AS mood_happy_mu,
        stddev_pop(mood_happy) AS mood_happy_sigma,
        avg(mood_relaxed) AS mood_relaxed_mu,
        stddev_pop(mood_relaxed) AS mood_relaxed_sigma
      FROM rows
    SQL

    DRIFT_TOLERANCE_RELATIVE = 0.25

    HEADS = %i[
      valence
      arousal
      danceability
      mood_acoustic
      mood_happy
      mood_relaxed
    ].freeze

    class << self
      def sample_size = SAMPLE_SIZE
      def heads = HEADS
      def mu = MU
      def sigma = SIGMA
      def reference_distance = REFERENCE_DISTANCE
      def finding_b_correlation = FINDING_B_CORRELATION
    end
  end
end
