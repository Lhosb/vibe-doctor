class FeedbackController < ApplicationController
  def index
    @event = RecommendationEvent.pending_for(current_user).first
  end
end
