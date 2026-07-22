class Album < ApplicationRecord
  class InvalidTransition < StandardError; end
  class InvalidYoutubeLinkError < StandardError; end

  YOUTUBE_URL_PATTERN = %r{\Ahttps://(www\.)?(youtube\.com|youtu\.be)/}

  ENRICHMENT_TRANSITIONS = {
    "pending" => %w[matching_audio failed],
    "matching_audio" => %w[extracting_features failed],
    "extracting_features" => %w[grounded failed],
    "grounded" => [],
    "failed" => %w[grounded]
  }.freeze

  has_one :mood_vector, dependent: :destroy
  has_one :vibe_card, dependent: :destroy
  has_one :embedding, dependent: :destroy
  has_many :collection_items, dependent: :destroy
  has_many :vibe_overrides, dependent: :destroy

  enum :enrichment_status, ENRICHMENT_TRANSITIONS.keys.index_by(&:itself), default: "pending", validate: true

  validates :master_id, presence: true, uniqueness: true
  validates :title, presence: true

  def start_matching!
    transition_to!("matching_audio")
  end

  def start_extracting!
    transition_to!("extracting_features")
  end

  def ground!
    transition_to!("grounded")
  end

  def fail_enrichment!
    transition_to!("failed")
  end

  def repair_youtube_link!(url)
    raise InvalidYoutubeLinkError, "url must be a youtube.com or youtu.be link" unless url.match?(YOUTUBE_URL_PATTERN)

    update!(youtube_url: url)
    transition_to!("grounded")
  end

  private

  def transition_to!(new_state)
    unless ENRICHMENT_TRANSITIONS.fetch(enrichment_status).include?(new_state)
      raise InvalidTransition, "cannot transition to #{new_state} from #{enrichment_status}"
    end

    update!(enrichment_status: new_state)
  end
end
