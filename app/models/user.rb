class User < ApplicationRecord
  has_secure_password
  has_secure_token :api_token
  has_many :sessions, dependent: :destroy
  has_many :collection_items, dependent: :destroy
  has_many :vibe_overrides, dependent: :destroy
  has_many :recommendation_events, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  encrypts :discogs_token

  validates :email_address, presence: true, uniqueness: true

  alias_method :regenerate_api_token!, :regenerate_api_token
end
