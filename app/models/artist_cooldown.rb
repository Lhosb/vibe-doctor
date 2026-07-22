class ArtistCooldown < ApplicationRecord
  COOLDOWN_DAYS = 14
  MAX_PENALTY = 0.5

  class_attribute :clock, default: -> { Time.current }

  belongs_to :user

  validates :user_id, uniqueness: { scope: :artist_name }

  def self.penalty_for(user:, artist_name:)
    cooldown = find_by(user: user, artist_name: artist_name)
    return 0.0 unless cooldown

    days_since = (clock.call - cooldown.last_recommended_at) / 1.day
    return 0.0 if days_since >= COOLDOWN_DAYS

    ((COOLDOWN_DAYS - days_since) / COOLDOWN_DAYS) * MAX_PENALTY
  end

  def self.record!(user:, artist_name:)
    cooldown = find_or_initialize_by(user: user, artist_name: artist_name)
    cooldown.update!(last_recommended_at: clock.call)
  end
end
