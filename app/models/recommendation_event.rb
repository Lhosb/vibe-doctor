class RecommendationEvent < ApplicationRecord
  belongs_to :user
  belongs_to :album

  validates :query_text, :candidates_considered, :final_score, presence: true
end
