require "json"
require "mood_probe"
require "pathname"
require "rbconfig"

root = Pathname(__dir__).join("../../..").expand_path
audio_dir = root.join("spec/fixtures/mood_probe/audio")
golden_dir = root.join("spec/fixtures/mood_probe/golden")
models_dir = root.join("tmp/essentia_models")
descriptors = %i[valence_emomusic arousal_emomusic danceability mood_acoustic mood_relaxed mood_happy]
extractor = MoodProbe::Extractor.new(models_dir:)
host_cpu = RbConfig::CONFIG.fetch("host_cpu")
abort("goldens require an amd64 runtime, got #{host_cpu}") unless %w[x86_64 amd64].include?(host_cpu)

golden_dir.mkpath

%w[chirp clicks sine_440 white_noise].each do |fixture_name|
  result = extractor.analyze(audio_dir.join("#{fixture_name}.wav"), descriptors:).to_h.transform_values(&:value)
  abort("#{fixture_name}: unexpected descriptors") unless result.keys == descriptors

  golden_dir.join("#{fixture_name}.json").write("#{JSON.pretty_generate(result)}\n")
end
