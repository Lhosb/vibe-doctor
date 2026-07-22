class VibeOverride < ApplicationRecord
  MOOD_HEADS = %w[valence arousal danceability mood_acoustic mood_relaxed mood_happy].freeze

  class MoodSnapshot
    attr_reader(*VibeOverride::MOOD_HEADS)

    def initialize(**attrs)
      VibeOverride::MOOD_HEADS.each { |head| instance_variable_set(:"@#{head}", attrs.fetch(head.to_sym)) }
    end
  end

  SOURCES = %w[vibe_map album_detail].freeze

  belongs_to :user
  belongs_to :album

  validates :album_id, uniqueness: { scope: :user_id }
  validates :source, inclusion: { in: SOURCES }

  def self.upsert_for!(user:, album:, mood_snapshot:, genre: nil, source:)
    override = find_or_initialize_by(user: user, album: album)
    override.update!(
      **MOOD_HEADS.index_with { |head| mood_snapshot.public_send(head) },
      genre: genre,
      source: source
    )
    override
  end

  def mood_snapshot
    MoodSnapshot.new(**MOOD_HEADS.index_with { |head| public_send(head) }.transform_keys(&:to_sym))
  end
end
