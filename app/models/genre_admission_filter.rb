class GenreAdmissionFilter
  DEFAULT_MARGIN = 0.08

  def initialize(candidates, requested_genre:, margin: DEFAULT_MARGIN)
    @candidates = candidates
    @requested_genre = requested_genre
    @margin = margin
  end

  def call
    return @candidates.sort_by(&:blended_score) if @requested_genre.blank?

    reference_score = @candidates.map(&:blended_score).min
    return [] if reference_score.nil?

    @candidates
      .select { |c| c.album.genres.include?(@requested_genre) || c.blended_score <= reference_score + @margin }
      .sort_by(&:blended_score)
  end
end
