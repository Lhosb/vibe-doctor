class FeedbackController < ApplicationController
  def index
    @event = pending_event_for(params[:recommendation_event_id])
  end

  def create
    event = current_user.recommendation_events.find(params.require(:recommendation_event_id))
    event.apply_outcome!(params.require(:outcome))

    @event = RecommendationEvent.pending_for(current_user).first
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to feedback_path }
    end
  rescue ActiveRecord::RecordNotFound
    head :not_found
  rescue RecommendationEvent::InvalidOutcomeTransitionError, ActionController::ParameterMissing
    head :unprocessable_content
  end

  private

  def pending_event_for(id)
    return RecommendationEvent.pending_for(current_user).first if id.blank?

    current_user.recommendation_events.pending.find_by(id: id) ||
      RecommendationEvent.pending_for(current_user).first
  end
end
