require "json"
require "mood_probe"
require "pathname"
require "spec_helper"

# Run in the Docker image, where essentia-tensorflow is installed:
#   docker build --platform linux/amd64 -t vibe-doctor-essentia-goldens .
#   docker run --rm --platform linux/amd64 --entrypoint bash \
#     -v "$PWD/spec/fixtures/mood_probe/golden:/rails/spec/fixtures/mood_probe/golden" \
#     vibe-doctor-essentia-goldens \
#     -c "ruby spec/fixtures/mood_probe/generate_goldens.rb"
#   docker run --rm --platform linux/amd64 --entrypoint bash \
#     -e ESSENTIA_SPECS=1 -e RAILS_ENV=test vibe-doctor-essentia-goldens \
#     -c "bundle exec rspec spec/integration/essentia_extract_golden_spec.rb --format documentation"
RSpec.describe "Essentia extraction goldens", :essentia do
  ROOT = Pathname(__dir__).join("../..").expand_path
  AUDIO_DIR = ROOT.join("spec/fixtures/mood_probe/audio")
  GOLDEN_DIR = ROOT.join("spec/fixtures/mood_probe/golden")
  MODELS_DIR = ROOT.join("tmp/essentia_models")
  MOOD_HEADS = %w[valence arousal danceability mood_acoustic mood_relaxed mood_happy].sort.freeze
  DECODABLE_FIXTURES = %w[chirp clicks sine_440 white_noise].freeze

  let(:extractor) { MoodProbe::Extractor.new(models_dir: MODELS_DIR) }

  DECODABLE_FIXTURES.each do |fixture_name|
    it "matches the #{fixture_name} golden output" do
      audio_path = AUDIO_DIR.join("#{fixture_name}.wav")
      expect(audio_path).to exist

      expected = JSON.parse(GOLDEN_DIR.join("#{fixture_name}.json").read, symbolize_names: true)
      features = extractor.analyze(audio_path)

      expect(features.to_h).to eq(expected)
      expect(expected.keys.map(&:to_s).sort).to eq(MOOD_HEADS)
    end
  end

  it "rejects undecodable audio" do
    audio_path = AUDIO_DIR.join("undecodable.m4a")
    expect(audio_path).to exist

    expect { extractor.analyze(audio_path) }.to raise_error(MoodProbe::UnreadableAudioError)
  end
end
