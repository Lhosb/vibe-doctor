module MoodScaleFixture
  FIXTURE_ROOT = Rails.root.join("spec/fixtures/mood_scale")

  def mood_scale_album_rows
    @mood_scale_album_rows ||= JSON.parse(File.read(FIXTURE_ROOT.join("catalogue_snapshot.json"))).fetch("rows")
  end

  def mood_scale_query_rows
    @mood_scale_query_rows ||= JSON.parse(File.read(FIXTURE_ROOT.join("queries.json")))
  end

  def mood_vector_from_fixture(row, mood_source:, album: nil)
    attributes = MoodVector::MOOD_HEADS.to_h do |head|
      [ head, row.fetch(head.to_s) ]
    end

    MoodVector.new(**attributes, mood_source:, album:)
  end
end

RSpec.configure do |config|
  config.include MoodScaleFixture
end
