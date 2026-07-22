class AlbumResource < Madmin::Resource
  # Attributes
  attribute :id, form: false
  attribute :artists
  attribute :created_at, form: false
  attribute :enrichment_status
  attribute :genres
  attribute :master_id
  attribute :styles
  attribute :synthetic_master_id
  attribute :title
  attribute :updated_at, form: false
  attribute :year
  attribute :youtube_url

  # Associations
  attribute :mood_vector
  attribute :vibe_card
  attribute :embedding
  attribute :collection_items
  attribute :vibe_overrides

  # Add scopes to easily filter records
  # scope :published

  member_action do |record|
    button_to "Repair YouTube Link",
      repair_youtube_link_madmin_album_path(record),
      method: :post,
      params: { youtube_url: record.youtube_url.presence || "https://www.youtube.com/watch?v=abc123" },
      class: "btn btn-secondary"
  end

  member_action do |record|
    button_to "Recommendation Stats",
      recommendation_stats_madmin_album_path(record),
      method: :get,
      class: "btn btn-secondary"
  end

  # Customize the display name of records in the admin area.
  # def self.display_name(record) = record.name

  # Customize the default sort column and direction.
  # def self.default_sort_column = "created_at"
  #
  # def self.default_sort_direction = "desc"
end
