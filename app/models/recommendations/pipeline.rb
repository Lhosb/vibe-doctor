module Recommendations
  class Pipeline
    class NoCandidatesError < StandardError; end

    Result = Struct.new(:album, :explanation, :recommendation_event, keyword_init: true)

    RERANK_TOP_K = 8
    SAMPLE_TEMPERATURE = 0.7

    def initialize(user:, query_text:, genre: nil)
      @user = user
      @query_text = query_text
      @genre = genre
    end

    def call
      understanding = QueryUnderstandingCache.fetch(@query_text)
      candidates = CandidateRetrieval.new(understanding, album_ids: user_album_ids).call
      admitted = GenreAdmissionFilter.new(candidates, requested_genre: @genre).call
      raise NoCandidatesError, "no albums matched the query" if admitted.empty?

      ranked = RankedCandidate.rank(candidates: admitted, user: @user)
      reranked = RerankClient.new.rerank(query_text: @query_text, ranked_candidates: ranked.first(RERANK_TOP_K))
      chosen = TemperatureSampler.new.sample(scored_items: reranked, temperature: SAMPLE_TEMPERATURE)

      event = persist_event(chosen: chosen, ranked: ranked, reranked: reranked, candidates_considered: admitted.size)
      record_cooldown!(chosen[:album])

      Result.new(album: chosen[:album], explanation: chosen[:rationale], recommendation_event: event)
    end

    private

    def record_cooldown!(album)
      album.artists.each { |artist_name| ArtistCooldown.record!(user: @user, artist_name: artist_name) }
    end

    def persist_event(chosen:, ranked:, reranked:, candidates_considered:)
      final_score = ranked.find { |r| r.album.id == chosen[:album].id }&.final_score || 0.0

      RecommendationEvent.create!(
        user: @user,
        album: chosen[:album],
        query_text: @query_text,
        candidates_considered: candidates_considered,
        blended_scores: ranked.to_h { |r| [ r.album.id.to_s, r.blended_score ] },
        rerank_scores: reranked.to_h { |r| [ r[:album].id.to_s, r[:rerank_score] ] },
        final_score: final_score,
        explanation: chosen[:rationale]
      )
    end

    def user_album_ids
      @user.collection_items.select(:album_id)
    end
  end
end
