require "mood_probe"
require "pathname"
require "spec_helper"
require "tmpdir"

RSpec.describe "Essentia extraction without model files", :essentia do
  AUDIO_PATH = Pathname(__dir__).join("../fixtures/mood_probe/audio/clicks.wav").expand_path

  it "extracts the click-train ground-truth tempo from an empty models directory" do
    Dir.mktmpdir do |models_dir|
      extractor = MoodProbe::Extractor.new(models_dir:)
      analysis = extractor.analyze(AUDIO_PATH, descriptors: [ :bpm ])

      expect(analysis[:bpm].value).to be_within(0.5).of(120.0)
      expect(Dir.children(models_dir)).to be_empty
    end
  end

  it "rejects a model-backed request without populating the empty directory" do
    Dir.mktmpdir do |models_dir|
      extractor = MoodProbe::Extractor.new(models_dir:)

      expect {
        extractor.analyze(AUDIO_PATH, descriptors: %i[bpm mood_happy])
      }.to raise_error(MoodProbe::ConfigurationError, /msd-musicnn-1\.pb/)
      expect(Dir.children(models_dir)).to be_empty
    end
  end
end
