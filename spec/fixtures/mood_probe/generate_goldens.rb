require "json"
require "mood_probe"
require "pathname"

root = Pathname(__dir__).join("../../..").expand_path
audio_dir = root.join("spec/fixtures/mood_probe/audio")
golden_dir = root.join("spec/fixtures/mood_probe/golden")
models_dir = root.join("tmp/essentia_models")
mood_heads = %w[valence arousal danceability mood_acoustic mood_relaxed mood_happy].sort
extractor = MoodProbe::Extractor.new(models_dir:)

golden_dir.mkpath

%w[chirp clicks sine_440 white_noise].each do |fixture_name|
  result = extractor.analyze(audio_dir.join("#{fixture_name}.wav")).to_h
  abort("#{fixture_name}: unexpected mood heads") unless result.keys.map(&:to_s).sort == mood_heads

  golden_dir.join("#{fixture_name}.json").write("#{JSON.pretty_generate(result)}\n")
end
