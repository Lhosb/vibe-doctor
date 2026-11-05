module Recommendations
  class RankedCandidate
    AFFINITY_WEIGHT = 0.35

    Ranked = Struct.new(:album, :blended_score, :affinity, :cooldown_penalty, :final_score, keyword_init: true)

    def self.rank(candidates:, user:)
      affinities = AlbumAffinity.scores_for(user: user, albums: candidates.map(&:album))

      candidates.map { |candidate|
        similarity = 1.0 / (1.0 + candidate.blended_score)
        affinity = affinities.fetch(candidate.album.id, 0.0)
        cooldown_penalty = cooldown_penalty_for(candidate.album, user)

        Ranked.new(
          album: candidate.album,
          blended_score: candidate.blended_score,
          affinity: affinity,
          cooldown_penalty: cooldown_penalty,
          final_score: similarity + (AFFINITY_WEIGHT * affinity) - cooldown_penalty
        )
      }.sort_by { |ranked| -ranked.final_score }
    end

    def self.cooldown_penalty_for(album, user)
      album.artists.map { |artist_name| ArtistCooldown.penalty_for(user: user, artist_name: artist_name) }.max || 0.0
    end
    private_class_method :cooldown_penalty_for
  end
end
