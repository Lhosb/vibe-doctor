module MoodVectors
  class CatalogueScale
    VERSION = "2026-08-14-v3".freeze

    # Measured on vibe_doctor_development, 2026-08-14.
    # Row filter: mood_source LIKE 'essentia%'. n = 321 (essentia_itunes=314, essentia_youtube=7).
    # NOTE: production representativeness is unverified.
    SAMPLE_SIZE = 321

    # Per-head mean (mu) in stored 0..1 space.
    MU = {
      valence: 0.5113469703,
      arousal: 0.4924708821,
      danceability: 0.5288407371,
      mood_acoustic: 0.4234423973,
      mood_happy: 0.5453354621,
      mood_relaxed: 0.5285604759
    }.freeze

    # Per-head population standard deviation (sigma) in stored 0..1 space.
    SIGMA = {
      valence: 0.0592340732,
      arousal: 0.0870053745,
      danceability: 0.3348149979,
      mood_acoustic: 0.3208211343,
      mood_happy: 0.2689669437,
      mood_relaxed: 0.3136104494
    }.freeze

    # Baseline median pairwise standardized distance over grounded catalog rows in z-space.
    # This is d_z from principal.md §4.2, not stored-space Euclidean distance in 0..1.
    # The constant is published to 10dp; re-derivation from published SIGMA is stable to 9dp
    # because the tenth digit comes from full-precision sigma used during measurement.
    REFERENCE_DISTANCE = 3.0217250259

    # Finding B limitation (principal.md §3.5): the six heads are not six independent dimensions.
    # In the measured catalog, corr(arousal, mood_relaxed) = -0.9014. Per-head standardization
    # therefore still weights the energy/relaxation axis more than an independent axis would.
    # corr(valence, arousal) = +0.7146 matters because these are the two EMOMUSIC heads raised
    # to parity in this track, so their contribution is closer to ~1.7 effective dimensions than 2.
    # This limitation is declared, not solved, in this ticket.
    FINDING_B_CORRELATION = {
      arousal_vs_mood_relaxed: -0.9014,
      valence_vs_arousal: 0.7146
    }.freeze

    # Drift check query for reviewer/operator inspection against grounded catalog rows.
    # The executable drift gate used by specs is implemented by recompute_statistics + drift_report.
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

      def recompute_statistics(scope:)
        rows = scope.pluck(*HEADS)
        row_count = rows.size
        raise ArgumentError, "drift check requires grounded mood rows" if row_count.zero?

        values_by_head = rows.transpose
        observed_mu = {}
        observed_sigma = {}

        HEADS.each_with_index do |head, index|
          values = values_by_head.fetch(index)
          mean = values.sum.fdiv(row_count)
          variance = values.sum { |value| (value - mean)**2 }.fdiv(row_count)

          observed_mu[head] = mean
          observed_sigma[head] = Math.sqrt(variance)
        end

        {
          row_count:,
          mu: observed_mu.freeze,
          sigma: observed_sigma.freeze
        }.freeze
      end

      def evaluate_sigma_drift(observed_sigma:, baseline_sigma: SIGMA, tolerance_relative: DRIFT_TOLERANCE_RELATIVE)
        relative_drift = HEADS.index_with do |head|
          baseline = baseline_sigma.fetch(head).to_f
          observed = observed_sigma.fetch(head).to_f
          ((observed - baseline).abs / baseline)
        end

        breaches = relative_drift.filter_map do |head, drift|
          head if drift > tolerance_relative
        end

        {
          row_count: nil,
          tolerance_relative:,
          relative_drift: relative_drift.freeze,
          breaches: breaches.freeze,
          within_tolerance: breaches.empty?
        }.freeze
      end

      def drift_report(scope:, baseline_sigma: SIGMA, tolerance_relative: DRIFT_TOLERANCE_RELATIVE)
        stats = recompute_statistics(scope:)
        drift = evaluate_sigma_drift(
          observed_sigma: stats.fetch(:sigma),
          baseline_sigma:,
          tolerance_relative:
        )

        {
          row_count: stats.fetch(:row_count),
          mu: stats.fetch(:mu),
          sigma: stats.fetch(:sigma),
          tolerance_relative: drift.fetch(:tolerance_relative),
          relative_drift: drift.fetch(:relative_drift),
          breaches: drift.fetch(:breaches),
          within_tolerance: drift.fetch(:within_tolerance)
        }.freeze
      end

      def reference_distance_report(scope:)
        rows = scope.pluck(*HEADS)
        row_count = rows.size
        raise ArgumentError, "reference distance check requires grounded mood rows" if row_count.zero?

        distances = []
        rows.each_with_index do |left, left_index|
          ((left_index + 1)...rows.length).each do |right_index|
            right = rows.fetch(right_index)
            squared = HEADS.each_with_index.sum do |head, dim|
              ((left.fetch(dim) - right.fetch(dim)) / SIGMA.fetch(head))**2
            end
            distances << Math.sqrt(squared)
          end
        end

        sorted = distances.sort
        mid = sorted.length / 2
        reference = if sorted.length.odd?
          sorted.fetch(mid)
        else
          (sorted.fetch(mid - 1) + sorted.fetch(mid)) / 2.0
        end

        {
          row_count:,
          pair_count: distances.length,
          reference_distance_from_constants: reference
        }.freeze
      end

      private
    end
  end
end
