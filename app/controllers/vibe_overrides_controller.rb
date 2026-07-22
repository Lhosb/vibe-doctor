class VibeOverridesController < ApplicationController
  def create
    album = Album.find(params.require(:album_id))
    mood_snapshot = VibeOverride::MoodSnapshot.new(
      valence: params.require(:valence).to_f,
      arousal: params.require(:arousal).to_f,
      danceability: params.require(:danceability).to_f,
      mood_acoustic: params.require(:mood_acoustic).to_f,
      mood_relaxed: params.require(:mood_relaxed).to_f,
      mood_happy: params.require(:mood_happy).to_f
    )

    override = VibeOverride.upsert_for!(
      user: current_user,
      album: album,
      mood_snapshot: mood_snapshot,
      genre: params[:genre],
      source: params.require(:source)
    )

    render json: { album_id: album.id, source: override.source }, status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: { error: "album not found" }, status: :not_found
  rescue ActionController::ParameterMissing => e
    render json: { error: e.message }, status: :bad_request
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_content
  end
end
