require "rails_helper"

RSpec.describe AlbumAffinity do
  describe ".scores_for" do
    let(:user) { create(:user) }
    let(:scored_album) { create(:album, :grounded) }
    let(:unscored_album) { create(:album, :grounded) }

    before { create(:album_affinity, user: user, album: scored_album, score: 0.42) }

    it "returns known scores and defaults missing albums to 0.0" do
      scores = described_class.scores_for(user: user, albums: [scored_album, unscored_album])

      expect(scores[scored_album.id]).to eq(0.42)
      expect(scores[unscored_album.id]).to be_nil # caller applies the 0.0 default via Hash#fetch
    end
  end

  it "enforces one affinity row per user/album pair" do
    user = create(:user)
    album = create(:album, :grounded)
    create(:album_affinity, user: user, album: album)

    expect { create(:album_affinity, user: user, album: album) }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
