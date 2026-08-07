# Regenerate the deleted app script and compare it with the gem in one container:
#   git show 96e546f:script/essentia_extract.py > /tmp/essentia_extract_phase2.py
#   docker build --platform linux/amd64 -t vibe-doctor-phase3-parity .
#   docker run --rm --platform linux/amd64 --entrypoint bash \
#     -e OLD_ESSENTIA_SCRIPT=/tmp/essentia_extract_phase2.py \
#     -v /tmp/essentia_extract_phase2.py:/tmp/essentia_extract_phase2.py:ro \
#     vibe-doctor-phase3-parity \
#     -c "bundle exec ruby spec/support/phase3_parity.rb"

require "json"
require "mood_probe"
require "open3"
require "pathname"

module Phase3Parity
  module_function

  def run
    root = Pathname("/rails")
    audio_dir = root.join("spec/fixtures/mood_probe/audio")
    models_dir = root.join("tmp/essentia_models")
    script_path = Pathname(ENV.fetch("OLD_ESSENTIA_SCRIPT"))
    extractor = MoodProbe::Extractor.new(models_dir:)

    %w[chirp clicks sine_440 white_noise].each do |name|
      audio_path = audio_dir.join("#{name}.wav")
      stdout, stderr, status = Open3.capture3(
        "python3", script_path.to_s, audio_path.to_s, "--models-dir", models_dir.to_s
      )
      abort("#{name} old path failed: #{stderr}") unless status.success?

      old_features = JSON.parse(stdout)
      new_features = extractor.analyze(audio_path).to_h.transform_keys(&:to_s)
      abort("#{name} mismatch:\nold=#{old_features}\nnew=#{new_features}") unless old_features == new_features

      puts "#{name}: #{JSON.generate(new_features)}"
    end

    puts "old/new parity: bit-identical"
  end
end

Phase3Parity.run if $PROGRAM_NAME == __FILE__
