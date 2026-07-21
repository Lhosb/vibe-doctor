class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :collection_items, dependent: :destroy
  has_many :vibe_overrides, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  encrypts :discogs_token

  validates :email_address, presence: true, uniqueness: true
end
