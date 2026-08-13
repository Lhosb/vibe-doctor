require "json"
require "sonance"
require "pathname"
require "spec_helper"

# Run in the Docker image, where essentia-tensorflow is installed:
#   docker build --platform linux/amd64 -t vibe-doctor-essentia-goldens .
#   docker run --rm --platform linux/amd64 --entrypoint bash \
#     -v "$PWD/spec/fixtures/sonance/golden:/rails/spec/fixtures/sonance/golden" \
#     vibe-doctor-essentia-goldens \
#     -c "ruby spec/fixtures/sonance/generate_goldens.rb"
#   docker run --rm --platform linux/amd64 --entrypoint bash \
#     -e ESSENTIA_SPECS=1 -e RAILS_ENV=test vibe-doctor-essentia-goldens \
#     -c "bundle exec rspec spec/integration/essentia_extract_golden_spec.rb --format documentation"
RSpec.describe "Essentia extraction goldens", :essentia do
  ROOT = Pathname(__dir__).join("../..").expand_path
  AUDIO_DIR = ROOT.join("spec/fixtures/sonance/audio")
  GOLDEN_DIR = ROOT.join("spec/fixtures/sonance/golden")
  MODELS_DIR = ROOT.join("tmp/essentia_models")
  DESCRIPTORS = %i[
    valence_emomusic arousal_emomusic danceability_musicnn mood_acoustic_musicnn
    mood_relaxed_musicnn mood_happy_musicnn
  ].freeze
  DECODABLE_FIXTURES = %w[chirp clicks sine_440 white_noise].freeze
  # Relative-bound heads are 10x tighter than Phase 4's 1e-3 ONNX gate; the floor-bound head is ~1.5x tighter.
  # Calibration control: a 0.900e-04 chirp.valence perturbation passed, while 1.100e-04 failed.
  # This tolerance is load-bearing because emulation generated the goldens while native x86_64 CI extracts them;
  # tightening it toward exact equality would break this intentional cross-environment configuration.
  GOLDEN_REL_TOL = 1e-4
  GOLDEN_ABS_FLOOR = 1e-10
  CPU_IDENTIFIER = (
    File.exist?("/proc/cpuinfo") && File.read("/proc/cpuinfo")[/^model name\s*:\s*(.+)$/, 1] || "unknown CPU"
  ).freeze

  let(:extractor) { Sonance::Extractor.new(models_dir: MODELS_DIR) }

  DECODABLE_FIXTURES.each do |fixture_name|
    it "matches the #{fixture_name} golden output" do
      audio_path = AUDIO_DIR.join("#{fixture_name}.wav")
      expect(audio_path).to exist

      expected = JSON.parse(GOLDEN_DIR.join("#{fixture_name}.json").read, symbolize_names: true)
      analysis = extractor.analyze(audio_path, descriptors: DESCRIPTORS)
      actual = analysis.to_h.transform_values(&:value)

      expect(actual.keys).to eq(DESCRIPTORS)
      expect(expected.keys).to eq(DESCRIPTORS)

      comparisons = expected.to_h do |head, expected_value|
        actual_value = actual.fetch(head)
        absolute_deviation = (actual_value - expected_value).abs
        # Nonzero drift from an exact zero has no finite relative deviation, so it must dominate the diagnostic ranking.
        relative_deviation = if expected_value.zero?
          absolute_deviation.zero? ? 0.0 : Float::INFINITY
        else
          absolute_deviation / expected_value.abs
        end
        tolerance = [ GOLDEN_REL_TOL * expected_value.abs, GOLDEN_ABS_FLOOR ].max
        puts "#{fixture_name}.#{head}: abs #{format("%.3e", absolute_deviation)}, " \
             "rel #{format("%.3e", relative_deviation)}, tolerance #{format("%.3e", tolerance)}"

        [ head, { actual: actual_value, expected: expected_value, absolute_deviation:, relative_deviation:, tolerance: } ]
      end
      max_head, max_comparison = comparisons.max_by do |_head, comparison|
        deviation = comparison.fetch(:relative_deviation)
        # An actual NaN propagates through the arithmetic; rank it first so the assertion names its head.
        deviation.nan? ? Float::INFINITY : deviation
      end
      diagnostic = "#{fixture_name}: max rel dev #{format("%.3e", max_comparison.fetch(:relative_deviation))} " \
        "on #{max_head} [cpu: #{CPU_IDENTIFIER}]"

      puts diagnostic

      comparisons.each do |head, comparison|
        expect(comparison.fetch(:absolute_deviation)).to be <= comparison.fetch(:tolerance),
          "#{diagnostic}; #{head} expected #{comparison.fetch(:expected)}, " \
          "got #{comparison.fetch(:actual)}, tolerance #{comparison.fetch(:tolerance)}"
      end
    end
  end

  it "rejects undecodable audio" do
    audio_path = AUDIO_DIR.join("undecodable.m4a")
    expect(audio_path).to exist

    expect {
      extractor.analyze(audio_path, descriptors: DESCRIPTORS)
    }.to raise_error(Sonance::UnreadableAudioError)
  end
end
