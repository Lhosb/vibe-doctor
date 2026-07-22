class RecommendationsController < ApplicationController
  def create
    result = RecommendationPipeline.new(
      user: Current.user,
      query_text: params.require(:query),
      genre: params[:genre]
    ).call

    render json: {
      recommendation_event_id: result.recommendation_event.id,
      album: {
        id: result.album.id,
        title: result.album.title,
        artists: result.album.artists,
        genres: result.album.genres
      },
      explanation: result.explanation
    }, status: :ok
  rescue RecommendationPipeline::NoCandidatesError => e
    render json: { error: e.message }, status: :unprocessable_content
  rescue ActionController::ParameterMissing => e
    render json: { error: e.message }, status: :bad_request
  end

  def feedback
    event = RecommendationEvent.find(params.require(:recommendation_event_id))
    event.apply_outcome!(params.require(:outcome))

    render json: {
      recommendation_event_id: event.id,
      outcome: event.outcome,
      album_affinity_score: AlbumAffinity.find_by(user: event.user, album: event.album)&.score
    }, status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: { error: "recommendation event not found" }, status: :not_found
  rescue ActionController::ParameterMissing => e
    render json: { error: e.message }, status: :bad_request
  rescue RecommendationEvent::InvalidOutcomeTransitionError => e
    render json: { error: e.message }, status: :unprocessable_content
  end
end
