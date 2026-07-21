require "open3"
require "securerandom"
require "tmpdir"
require "json"

class YoutubeClipMatcher
  CLIP_START_SECONDS = 60
  CLIP_DURATION_SECONDS = 45
  SOCKET_TIMEOUT_SECONDS = 30

  def initialize(yt_dlp_executable: "yt-dlp")
    @yt_dlp_executable = yt_dlp_executable
  end

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
      @yt_dlp_executable, "ytsearch#{limit}:#{term}",
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
    dest_dir = Dir.mktmpdir("vibe_doctor_yt_")
    dest_template = File.join(dest_dir, "#{SecureRandom.hex}.%(ext)s")

    _stdout, _stderr, status = Open3.capture3(
      @yt_dlp_executable, "https://www.youtube.com/watch?v=#{video_id}",
      "--format", "bestaudio/best",
      "--download-sections", "*#{CLIP_START_SECONDS}-#{CLIP_START_SECONDS + CLIP_DURATION_SECONDS}",
      "--force-keyframes-at-cuts",
      "--output", dest_template,
      "--quiet", "--no-warnings",
      "--socket-timeout", SOCKET_TIMEOUT_SECONDS.to_s
    )
    return nil unless status.success?

    Dir.glob(File.join(dest_dir, "*")).first
  end
end
