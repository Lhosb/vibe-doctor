require "open3"
require "securerandom"
require "tmpdir"
require "json"
require "tempfile"

class YoutubeClipMatcher
  CLIP_START_SECONDS = 60
  CLIP_DURATION_SECONDS = 45
  SOCKET_TIMEOUT_SECONDS = 30
  YT_DLP_EXECUTABLE = "yt-dlp".freeze

  # Downloading YouTube audio for algorithmic analysis is a legal gray area.
  # Callers MUST delete every returned file immediately after analysis; only
  # the derived mood vector is ever persisted.
  def find_clips(title:, artists:, confidence_threshold:, max_clips: 3)
    term = SearchTermBuilder.clean_search_term(title, artists)
    results = search(term, max_clips)

    results.filter_map do |result|
      confidence = FuzzyMatch.token_set_ratio(term, result[:title])
      next if confidence < confidence_threshold

      download_clip(result[:id])
    end
  end

  private

  def search(term, limit)
    stdout, _stderr, status = Open3.capture3(
      YT_DLP_EXECUTABLE, "ytsearch#{limit}:#{term}",
      "--flat-playlist", "--dump-json", "--quiet", "--no-warnings",
      "--socket-timeout", SOCKET_TIMEOUT_SECONDS.to_s
    )
    return [] unless status.success?

    stdout.each_line.filter_map do |line|
      entry = JSON.parse(line)
      { id: entry["id"], title: entry["title"].to_s }
    rescue JSON::ParserError
      nil
    end
  rescue Errno::ENOENT
    Rails.logger.warn("yt-dlp is not installed or not on PATH")
    []
  end

  def download_clip(video_id)
    Dir.mktmpdir("vibe_doctor_yt_") do |dest_dir|
      dest_template = File.join(dest_dir, "#{SecureRandom.hex}.%(ext)s")

      _stdout, _stderr, status = Open3.capture3(
        YT_DLP_EXECUTABLE, "https://www.youtube.com/watch?v=#{video_id}",
        "--format", "bestaudio/best",
        "--download-sections", "*#{CLIP_START_SECONDS}-#{CLIP_START_SECONDS + CLIP_DURATION_SECONDS}",
        "--force-keyframes-at-cuts",
        "--output", dest_template,
        "--quiet", "--no-warnings",
        "--socket-timeout", SOCKET_TIMEOUT_SECONDS.to_s
      )
      return nil unless status.success?

      clip_path = Dir.glob(File.join(dest_dir, "*")).first
      clip_path && persist_clip(clip_path)
    end
  end

  def persist_clip(source_path)
    destination = File.join(Dir.tmpdir, "vibe_doctor_yt_#{SecureRandom.hex}#{File.extname(source_path)}")
    File.binwrite(destination, File.binread(source_path))
    destination
  end
end
