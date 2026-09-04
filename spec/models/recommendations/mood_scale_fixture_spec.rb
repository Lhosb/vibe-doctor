require "rails_helper"

RSpec.describe "Mood-scale fixture integrity" do
  let(:fixture_path) { Rails.root.join("spec/fixtures/mood_scale/catalogue_snapshot.json") }
  let(:queries_path) { Rails.root.join("spec/fixtures/mood_scale/queries.json") }
  let(:baseline_path) { Rails.root.join("docs/superpowers/specs/2026-08-14-mood-scale/baseline.md") }
  let(:expected_fixture_sha256) { documented_sha_for("catalogue_snapshot.json") }
  let(:expected_queries_sha256) { documented_sha_for("queries.json") }

  it "pins one-user collection fixture integrity and non-vacuity floor (G11)" do
    payload = JSON.parse(File.read(fixture_path))
    queries = JSON.parse(File.read(queries_path))
    fixture = payload.fetch("rows")
    provenance = payload.fetch("_provenance")

    expect(Digest::SHA256.file(fixture_path).hexdigest).to eq(expected_fixture_sha256)
    expect(Digest::SHA256.file(queries_path).hexdigest).to eq(expected_queries_sha256)
    expect(fixture.size).to eq(321)
    expect(queries.size).to eq(12)
    expect(provenance.fetch("dataset_label")).to eq("one_user_personal_collection")
    expect(provenance.fetch("users_with_collection")).to eq(1)
    expect(provenance.fetch("grounded_albums_in_collection")).to eq(321)
  end

  it "reads album and query coordinates by head name (G12)" do
    album_row = JSON.parse(File.read(fixture_path)).fetch("rows").first
    query_row = JSON.parse(File.read(queries_path)).find { |query| query.fetch("id") == "q02" }

    expect(calibrated_album_coordinate(album_row, :mood_happy))
      .to eq(album_row.fetch("mood_happy"))
    expect(query_coordinate(query_row, :mood_happy)).to eq(query_row.fetch("mood_happy"))
  end

  def documented_sha_for(filename)
    baseline = File.read(baseline_path)
    match = baseline.match(/`[^`]*#{Regexp.escape(filename)}` \(SHA-256: `([0-9a-f]{64})`\)/)
    raise "missing SHA for #{filename} in baseline.md" unless match

    match[1]
  end

  def calibrated_album_coordinate(row, head)
    attributes = MoodVector::MOOD_HEADS.to_h do |mood_head|
      [ mood_head, row.fetch(mood_head.to_s) ]
    end
    mood_vector = Struct.new(*MoodVector::MOOD_HEADS, keyword_init: true).new(**attributes)

    MoodVectors::HeadCalibration.album_coordinate(mood_vector, head)
  end

  def query_coordinate(row, head)
    row.fetch(head.to_s)
  end
end
