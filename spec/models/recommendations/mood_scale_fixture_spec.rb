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

  it "provisionally reads album coordinates by head name (G12)" do
    album_row = JSON.parse(File.read(fixture_path)).fetch("rows").first

    expect(calibrated_album_coordinate(album_row, :mood_happy))
      .to eq(album_row.fetch("mood_happy"))
  end

  it "pins happy and relaxed fixture values to independent named anchors (G13)", :aggregate_failures do
    rows = JSON.parse(File.read(fixture_path)).fetch("rows")
    query = JSON.parse(File.read(queries_path)).find { |candidate| candidate.fetch("id") == "q02" }
    documented_query = documented_query_coordinates("q02")

    %w[mood_happy mood_relaxed].each do |head|
      expect(population_standard_deviation(rows, head))
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

  def calibrated_album_coordinate(row, head)
    attributes = MoodVector::MOOD_HEADS.to_h do |mood_head|
      [ mood_head, row.fetch(mood_head.to_s) ]
    end
    mood_vector = Struct.new(*MoodVector::MOOD_HEADS, keyword_init: true).new(**attributes)

    MoodVectors::HeadCalibration.album_coordinate(mood_vector, head)
  end

  def documented_population_standard_deviation(head)
    baseline = File.read(baseline_path)
    match = baseline.match(/`#{Regexp.escape(head)}` population standard deviation: `([0-9.]+)`/)
    raise "missing population standard deviation for #{head} in baseline.md" unless match

    match[1].to_f
  end

  def documented_query_coordinates(query_id)
    rows = File.readlines(baseline_path).grep(/^\|/)
    headers = rows.find { |line| line.start_with?("| id |") }.split("|").map(&:strip).reject(&:empty?)
    values = rows.find { |line| line.start_with?("| #{query_id} |") }.split("|").map(&:strip).reject(&:empty?)

    headers.zip(values).to_h.transform_values { |value| Float(value, exception: false) || value }
  end

  def population_standard_deviation(rows, head)
    values = rows.map { |row| row.fetch(head) }
    mean = values.sum / values.size

    Math.sqrt(values.sum { |value| (value - mean)**2 } / values.size)
  end
end
