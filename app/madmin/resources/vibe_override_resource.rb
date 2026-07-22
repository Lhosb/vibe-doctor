class VibeOverrideResource < Madmin::Resource
  # Attributes
  attribute :id, form: false
  attribute :arousal
  attribute :created_at, form: false
  attribute :danceability
  attribute :genre
  attribute :mood_acoustic
  attribute :mood_happy
  attribute :mood_relaxed
  attribute :source
  attribute :updated_at, form: false
  attribute :valence

  # Associations
  attribute :user
  attribute :album

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
