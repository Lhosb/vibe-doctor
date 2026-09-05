require "rails_helper"

RSpec.describe "Mood-scale fixture integrity" do
  let(:fixture_path) { Rails.root.join("spec/fixtures/mood_scale/catalogue_snapshot.json") }
  let(:queries_path) { Rails.root.join("spec/fixtures/mood_scale/queries.json") }
  let(:baseline_path) { Rails.root.join("docs/superpowers/specs/2026-08-14-mood-scale/baseline.md") }
  let(:expected_fixture_sha256) { documented_sha_for("catalogue_snapshot.json") }
  let(:expected_queries_sha256) { documented_sha_for("queries.json") }

  it "pins one-user collection fixture integrity and non-vacuity floor (G11)" do
    payload = JSON.parse(File.read(fixture_path))
    provenance = payload.fetch("_provenance")

    expect(Digest::SHA256.file(fixture_path).hexdigest).to eq(expected_fixture_sha256)
    expect(Digest::SHA256.file(queries_path).hexdigest).to eq(expected_queries_sha256)
    expect(mood_scale_album_rows.size).to eq(321)
    expect(mood_scale_query_rows.size).to eq(12)
    expect(provenance.fetch("dataset_label")).to eq("one_user_personal_collection")
    expect(provenance.fetch("users_with_collection")).to eq(1)
    expect(provenance.fetch("grounded_albums_in_collection")).to eq(321)
  end

  it "reads album coordinates through the shared named-key fixture reader (G12)" do
    album_row = mood_scale_album_rows.first
    album_mood = mood_vector_from_fixture(album_row, mood_source: "essentia_itunes")

    expect(MoodVectors::HeadCalibration.album_coordinate(album_mood, :mood_happy))
      .to eq(album_row.fetch("mood_happy"))
  end

  it "pins happy and relaxed fixture values to independent named anchors (G13)", :aggregate_failures do
    query = mood_scale_query_rows.find { |candidate| candidate.fetch("id") == "q02" }
    documented_query = documented_query_coordinates("q02")

    %w[mood_happy mood_relaxed].each do |head|
      expect(population_standard_deviation(mood_scale_album_rows, head))
        .to be_within(5e-7).of(documented_population_standard_deviation(head))
      expect(query.fetch(head)).to eq(documented_query.fetch(head))
    end
  end

  def documented_sha_for(filename)
    baseline = File.read(baseline_path)
    match = baseline.match(/`[^`]*#{Regexp.escape(filename)}` \(SHA-256: `([0-9a-f]{64})`\)/)
    raise "missing SHA for #{filename} in baseline.md" unless match

    match[1]
  end

  def documented_population_standard_deviation(head)
    baseline = File.read(baseline_path)
    match = baseline.match(/`#{Regexp.escape(head)}` population standard deviation: `([0-9.]+)`/)
    raise "missing population standard deviation for #{head} in baseline.md" unless match

    match[1].to_f
  end

  def documented_query_coordinates(query_id)
    baseline = File.read(baseline_path)

    %w[mood_happy mood_relaxed].to_h do |head|
      match = baseline.match(/query `#{Regexp.escape(query_id)}` `#{head}`: `([0-9.]+)`/)
      raise "missing #{head} anchor for #{query_id} in baseline.md" unless match

      [ head, match[1].to_f ]
    end
  end

  def population_standard_deviation(rows, head)
    values = rows.map { |row| row.fetch(head) }
    mean = values.sum / values.size

    Math.sqrt(values.sum { |value| (value - mean)**2 } / values.size)
  end
end
