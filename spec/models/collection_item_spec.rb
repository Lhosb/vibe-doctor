require "rails_helper"

RSpec.describe CollectionItem, type: :model do
  let(:user) { create(:user) }
  let(:album) { Album.create!(master_id: 1, title: "Nevermind") }

  it "is valid with a user, album, and release_id" do
    expect(CollectionItem.new(user: user, album: album, release_id: 249_504)).to be_valid
  end

  it "requires a release_id unique per user" do
    CollectionItem.create!(user: user, album: album, release_id: 249_504)
    other_album = Album.create!(master_id: 2, title: "In Utero")
    duplicate = CollectionItem.new(user: user, album: other_album, release_id: 249_504)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:release_id]).to be_present
  end

  it "allows the same release_id for two different users" do
    CollectionItem.create!(user: user, album: album, release_id: 249_504)
    other_user = create(:user)
    expect(CollectionItem.new(user: other_user, album: album, release_id: 249_504)).to be_valid
  end
end
