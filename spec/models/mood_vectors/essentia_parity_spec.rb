require "fileutils"
require "json"
require "rails_helper"
require "tmpdir"

RSpec.describe "Essentia mood vector parity" do
  FIXTURES = %w[chirp clicks sine_440 white_noise].freeze
  DESCRIPTOR_TO_HEAD = {
    valence_emomusic: :valence,
    arousal_emomusic: :arousal,
    danceability_musicnn: :danceability,
    mood_acoustic_musicnn: :mood_acoustic,
    mood_relaxed_musicnn: :mood_relaxed,
    mood_happy_musicnn: :mood_happy
  }.freeze
  GOLDEN_ROOT = Rails.root.join("spec/fixtures/sonance/golden")
  BASELINE_ROOT = Rails.root.join("spec/fixtures/sonance/baseline_v0_1_0")
  RELATIVE_TOLERANCE = 1e-4
  ABSOLUTE_FLOOR = 1e-10
  # Calibration control: a literal 0.900e-04 chirp.mood_happy perturbation passes, while 1.100e-04 fails.
  # These literals are load-bearing: deriving them from RELATIVE_TOLERANCE would let the control move with the bound.

  def fixture_names(root)
    root.glob("*.json").map { |path| path.basename(".json").to_s }.sort
  end

  def with_perturbed_baseline(relative_delta:)
    Dir.mktmpdir do |directory|
      baseline_root = Pathname(directory)
      FIXTURES.each do |fixture|
        FileUtils.cp(BASELINE_ROOT.join("#{fixture}.json"), baseline_root)
      end
      path = baseline_root.join("chirp.json")
      baseline = JSON.parse(path.read)
      baseline["mood_happy"] += relative_delta * baseline.fetch("mood_happy").abs
      path.write("#{JSON.pretty_generate(baseline)}\n")

      yield baseline_root
    end
  end

  def assert_parity(golden_root: GOLDEN_ROOT, baseline_root: BASELINE_ROOT)
    comparisons = 0

    FIXTURES.each do |fixture|
      golden = JSON.parse(golden_root.join("#{fixture}.json").read, symbolize_names: true)
      baseline = JSON.parse(baseline_root.join("#{fixture}.json").read, symbolize_names: true)

      DESCRIPTOR_TO_HEAD.each do |descriptor, head|
        native_value = golden.fetch(descriptor)
        actual = descriptor.to_s.end_with?("_emomusic") ? (native_value - 1.0) / 8.0 : native_value
        expected = baseline.fetch(head)
        absolute_deviation = (actual - expected).abs
        relative_deviation = absolute_deviation / expected.abs
        tolerance = [ RELATIVE_TOLERANCE * expected.abs, ABSOLUTE_FLOOR ].max
        comparisons += 1

        puts "#{fixture}.#{descriptor}: abs #{format("%.3e", absolute_deviation)}, " \
             "rel #{format("%.3e", relative_deviation)}, tolerance #{format("%.3e", tolerance)}"
        expect(absolute_deviation).to be <= tolerance,
          "#{fixture}.json golden #{descriptor}: expected #{expected}, got #{actual}, tolerance #{tolerance}"
      end
    end

    comparisons
  end

  it "executes all 24 frozen-baseline comparisons", :aggregate_failures do
    expect(fixture_names(GOLDEN_ROOT)).to eq(FIXTURES)
    expect(fixture_names(BASELINE_ROOT)).to eq(FIXTURES)
    expect(assert_parity).to eq(24)
  end

  it "accepts a calibration perturbation just inside the parity bound" do
    with_perturbed_baseline(relative_delta: 0.9e-4) do |baseline_root|
      expect(assert_parity(baseline_root:)).to eq(24)
    end
  end

  it "rejects a calibration perturbation just outside the parity bound with an attributable failure" do
    with_perturbed_baseline(relative_delta: 1.1e-4) do |baseline_root|
      expect { assert_parity(baseline_root:) }
        .to raise_error(RSpec::Expectations::ExpectationNotMetError, /chirp\.json golden mood_happy_musicnn/)
    end
  end

  FIXTURES.each do |fixture|
    it "maps the #{fixture} golden to the frozen mood vector" do
      golden = JSON.parse(GOLDEN_ROOT.join("#{fixture}.json").read, symbolize_names: true)
      baseline = JSON.parse(BASELINE_ROOT.join("#{fixture}.json").read, symbolize_names: true)
      analysis = Sonance::AnalysisBuilder.new(registry: Sonance::Registry.default).call(
        requested: MoodVectors::EssentiaMapper::DESCRIPTORS,
        raw_values: golden
      )
      result = MoodVectors::EssentiaMapper.new.call(analysis.to_h.transform_values(&:value))

      expect(MoodVector::MOOD_HEADS.size).to eq(6)
      expect(result.keys).to eq(MoodVector::MOOD_HEADS)
      MoodVector::MOOD_HEADS.each do |head|
        tolerance = [ RELATIVE_TOLERANCE * baseline.fetch(head).abs, ABSOLUTE_FLOOR ].max
        expect((result.fetch(head) - baseline.fetch(head)).abs).to be <= tolerance
      end
    end
  end
end
