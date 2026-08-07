require "json"
require "open3"
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
  SCRIPT_PATH = ROOT.join("script/essentia_extract.py")
  MOOD_HEADS = %w[valence arousal danceability mood_acoustic mood_relaxed mood_happy].sort.freeze
  DECODABLE_FIXTURES = %w[chirp clicks sine_440 white_noise].freeze

  DECODABLE_FIXTURES.each do |fixture_name|
    it "matches the #{fixture_name} golden output" do
      audio_path = AUDIO_DIR.join("#{fixture_name}.wav")
      expect(audio_path).to exist

      expected = JSON.parse(GOLDEN_DIR.join("#{fixture_name}.json").read)
      stdout, stderr, status = Open3.capture3(
        "python3", SCRIPT_PATH.to_s, audio_path.to_s, "--models-dir", MODELS_DIR.to_s
      )

      expect(status).to be_success, stderr
      expect(JSON.parse(stdout)).to eq(expected)
      expect(expected.keys.sort).to eq(MOOD_HEADS)
    end
  end

  it "rejects undecodable audio" do
    audio_path = AUDIO_DIR.join("undecodable.m4a")
    expect(audio_path).to exist

    stdout, stderr, status = Open3.capture3(
      "python3", SCRIPT_PATH.to_s, audio_path.to_s, "--models-dir", MODELS_DIR.to_s
    )

    expect(status).not_to be_success
    expect(stdout).to be_empty
    expect(stderr).to include("essentia_extract failed:")
  end
end
