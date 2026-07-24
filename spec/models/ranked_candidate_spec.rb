require "rails_helper"

RSpec.describe RankedCandidate do
  let(:user) { create(:user) }
  let(:favored_album) { create(:album, :grounded, artists: [ "Favored Artist" ]) }
  let(:cooled_album) { create(:album, :grounded, artists: [ "Cooled Artist" ]) }
  let(:candidates) do
    [
      CandidateRetrieval::Candidate.new(album: favored_album, blended_score: 0.30),
      CandidateRetrieval::Candidate.new(album: cooled_album, blended_score: 0.30)
    ]
  end

  before do
    create(:album_affinity, user: user, album: favored_album, score: 1.0)
    create(:artist_cooldown, user: user, artist_name: "Cooled Artist", last_recommended_at: 1.day.ago)
  end

  it "ranks a favored album above an equally-scored cooled album" do
    ranked = described_class.rank(candidates: candidates, user: user)

    expect(ranked.first.album).to eq(favored_album)
    expect(ranked.last.cooldown_penalty).to be > 0.0
  end

  it "takes the max cooldown penalty across a multi-artist album's credited artists" do
    collab_album = create(:album, :grounded, artists: [ "Someone Else", "Cooled Artist" ])
    create(:artist_cooldown, user: user, artist_name: "Someone Else", last_recommended_at: 13.days.ago)
    collab_candidates = [ CandidateRetrieval::Candidate.new(album: collab_album, blended_score: 0.30) ]

    ranked = described_class.rank(candidates: collab_candidates, user: user)
    expected_penalty = ArtistCooldown.penalty_for(user: user, artist_name: "Cooled Artist")

    expect(ranked.first.cooldown_penalty).to be_within(0.0001).of(expected_penalty)
  end
end
