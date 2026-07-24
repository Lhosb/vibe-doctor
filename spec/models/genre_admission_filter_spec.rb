require "rails_helper"

RSpec.describe GenreAdmissionFilter do
  let(:jazz) { build_stubbed(:album, genres: [ "Jazz" ]) }
  let(:rock) { build_stubbed(:album, genres: [ "Rock" ]) }
  let(:candidates) do
    [
      CandidateRetrieval::Candidate.new(album: jazz, blended_score: 0.20),
      CandidateRetrieval::Candidate.new(album: rock, blended_score: 0.24) # within default margin of 0.08
    ]
  end

  it "returns all candidates when no genre is requested" do
    result = described_class.new(candidates, requested_genre: nil).call
    expect(result.map(&:album)).to contain_exactly(jazz, rock)
  end

  it "admits an out-of-genre candidate within the margin of the best score" do
    result = described_class.new(candidates, requested_genre: "Jazz", margin: 0.08).call
    expect(result.map(&:album)).to contain_exactly(jazz, rock)
  end

  it "excludes an out-of-genre candidate outside the margin" do
    result = described_class.new(candidates, requested_genre: "Jazz", margin: 0.01).call
    expect(result.map(&:album)).to contain_exactly(jazz)
  end
end
