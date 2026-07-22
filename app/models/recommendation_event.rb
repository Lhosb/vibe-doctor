class RecommendationEvent < ApplicationRecord
  class InvalidOutcomeTransitionError < StandardError; end

  REWARD_BY_OUTCOME = { "good" => 0.15, "bad" => -0.20, "skip" => -0.05 }.freeze
  AFFINITY_SCORE_RANGE = (-1.0..1.0)

  belongs_to :user
  belongs_to :album

  enum :outcome, { pending: "pending", good: "good", bad: "bad", skip: "skip" }, default: "pending"

  validates :query_text, :candidates_considered, :final_score, presence: true

  scope :pending_for, ->(user) { where(user: user, outcome: "pending").order(:created_at) }

  def apply_outcome!(new_outcome)
    unless REWARD_BY_OUTCOME.key?(new_outcome.to_s)
      raise InvalidOutcomeTransitionError, "outcome must be one of #{REWARD_BY_OUTCOME.keys}"
    end
    raise InvalidOutcomeTransitionError, "event #{id} already has outcome #{outcome}" unless pending?

    transaction do
      update!(outcome: new_outcome)
      apply_reward!
    end
  end

  private

  def apply_reward!
    affinity = AlbumAffinity.find_or_initialize_by(user: user, album: album)
    reward = REWARD_BY_OUTCOME.fetch(outcome)
    affinity.score = (affinity.score + reward).clamp(AFFINITY_SCORE_RANGE)
    affinity.last_interacted_at = Time.current
    affinity.save!
  end
end
