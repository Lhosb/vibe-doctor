require "json"
require "open3"
require "pathname"

root = Pathname(__dir__).join("../../..").expand_path
audio_dir = root.join("spec/fixtures/mood_probe/audio")
golden_dir = root.join("spec/fixtures/mood_probe/golden")
models_dir = root.join("tmp/essentia_models")
script_path = root.join("script/essentia_extract.py")
mood_heads = %w[valence arousal danceability mood_acoustic mood_relaxed mood_happy].sort

golden_dir.mkpath

%w[chirp clicks sine_440 white_noise].each do |fixture_name|
  stdout, stderr, status = Open3.capture3(
    "python3", script_path.to_s, audio_dir.join("#{fixture_name}.wav").to_s,
    "--models-dir", models_dir.to_s
  )
  abort(stderr) unless status.success?

  result = JSON.parse(stdout)
  abort("#{fixture_name}: unexpected mood heads") unless result.keys.sort == mood_heads

  golden_dir.join("#{fixture_name}.json").write("#{JSON.pretty_generate(result)}\n")
end
