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

  # Associations
  attribute :mood_vector
  attribute :vibe_card
  attribute :embedding
  attribute :collection_items
  attribute :vibe_overrides

  # Add scopes to easily filter records
  # scope :published

  # Add actions to the resource's show page
  # member_action do |record|
  #   link_to "Do Something", some_path
  # end

  # Customize the display name of records in the admin area.
  # def self.display_name(record) = record.name

  # Customize the default sort column and direction.
  # def self.default_sort_column = "created_at"
  #
  # def self.default_sort_direction = "desc"
end
