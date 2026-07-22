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
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActionController::ParameterMissing => e
    render json: { error: e.message }, status: :bad_request
  end
end
