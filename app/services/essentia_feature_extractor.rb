require "open3"
require "json"

class EssentiaFeatureExtractor
  class Error < StandardError; end

  SCRIPT_PATH = Rails.root.join("script", "essentia_extract.py").to_s

  def initialize(models_dir:, python_executable: "python3")
    @models_dir = models_dir
    @python_executable = python_executable
  end

  def analyze(audio_path)
    stdout, stderr, status = Open3.capture3(
      @python_executable, SCRIPT_PATH, audio_path.to_s, "--models-dir", @models_dir.to_s
    )
    raise Error, stderr.presence || "essentia_extract exited #{status.exitstatus}" unless status.success?

    JSON.parse(stdout).transform_keys(&:to_sym).transform_values(&:to_f)
  rescue JSON::ParserError => e
    raise Error, "essentia_extract produced invalid JSON: #{e.message}"
  end
end
