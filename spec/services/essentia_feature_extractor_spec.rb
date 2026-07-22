require "rails_helper"

RSpec.describe EssentiaFeatureExtractor do
  subject(:extractor) { described_class.new(models_dir: Pathname.new("/fake/models")) }

  let(:script_path) { Rails.root.join("script", "essentia_extract.py").to_s }

  it "parses the script's JSON stdout into a symbol-keyed float hash" do
    allow(Open3).to receive(:capture3).with(
      "python3", script_path, "/tmp/track.m4a", "--models-dir", "/fake/models"
    ).and_return([
      '{"danceability": 0.6, "mood_acoustic": 0.1, "mood_relaxed": 0.4, "mood_happy": 0.5, "valence": 0.55, "arousal": 0.62}',
      "", instance_double(Process::Status, success?: true)
    ])

    result = extractor.analyze("/tmp/track.m4a")

    expect(result).to eq(
      danceability: 0.6, mood_acoustic: 0.1, mood_relaxed: 0.4, mood_happy: 0.5, valence: 0.55, arousal: 0.62
    )
  end

  it "raises EssentiaFeatureExtractor::Error when the script exits non-zero" do
    allow(Open3).to receive(:capture3).with("python3", script_path, "/tmp/track.m4a", "--models-dir", "/fake/models")
      .and_return(["", "essentia_extract failed: bad file", instance_double(Process::Status, success?: false)])

    expect { extractor.analyze("/tmp/track.m4a") }.to raise_error(EssentiaFeatureExtractor::Error, /bad file/)
  end

  it "raises EssentiaFeatureExtractor::Error when stdout isn't valid JSON" do
    allow(Open3).to receive(:capture3).with("python3", script_path, "/tmp/track.m4a", "--models-dir", "/fake/models")
      .and_return(["not json", "", instance_double(Process::Status, success?: true)])

    expect { extractor.analyze("/tmp/track.m4a") }.to raise_error(EssentiaFeatureExtractor::Error, /invalid JSON/)
  end
end
