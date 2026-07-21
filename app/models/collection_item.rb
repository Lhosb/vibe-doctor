class CollectionItem < ApplicationRecord
  belongs_to :user
  belongs_to :album

  validates :release_id, presence: true, uniqueness: { scope: :user_id }
end
