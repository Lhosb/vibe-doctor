class AlbumAffinity < ApplicationRecord
  belongs_to :user
  belongs_to :album

  validates :user_id, uniqueness: { scope: :album_id }

  def self.scores_for(user:, albums:)
    where(user: user, album_id: albums.map(&:id)).pluck(:album_id, :score).to_h
  end
end
