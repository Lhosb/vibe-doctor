require "rails_helper"

RSpec.describe "Mood-scale fixture integrity" do
  let(:fixture_path) { Rails.root.join("spec/fixtures/mood_scale/catalogue_snapshot.json") }
  let(:queries_path) { Rails.root.join("spec/fixtures/mood_scale/queries.json") }
  let(:expected_fixture_sha256) { "a2396eb1f52389235d37bedd5f1b63328f8bcdd6ef1ca8dde45055b2fee239b1" }

  it "pins one-user collection fixture integrity and non-vacuity floor (G11)" do
    fixture = JSON.parse(File.read(fixture_path))
    queries = JSON.parse(File.read(queries_path))

    expect(Digest::SHA256.file(fixture_path).hexdigest).to eq(expected_fixture_sha256)
    expect(fixture.size).to eq(321)
    expect(queries.size).to eq(12)
  end
end
