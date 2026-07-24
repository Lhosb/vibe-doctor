class AlbumResource < Madmin::Resource
  # Attributes
  attribute :id, form: false
  attribute :title
  attribute :artists
  attribute :artists_names, form: false, label: "Artists", index: true
  attribute :enrichment_status, index: true, form: false
  attribute :created_at, form: false
  attribute :genres
  attribute :master_id
  attribute :styles
  attribute :synthetic_master_id
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

  # Add filters to allow users to filter the index view
  # filter :title
  # filter :created_at
  # filter :updated_at

  # Add custom validations to the resource
  # validate do
  #   errors.add :base, "Something went wrong"
  # end

  # Add custom actions to the resource

  member_action do |record|
    form_with url: repair_youtube_link_madmin_album_path(record), method: :post, local: true do
      safe_join([
        text_field_tag(:youtube_url, record.youtube_url, placeholder: "https://www.youtube.com/watch?v=...", class: "form-input"),
        submit_tag("Repair YouTube Link", class: "btn btn-secondary")
      ])
    end
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
