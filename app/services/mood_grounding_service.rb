require "securerandom"

class MoodGroundingService
  def initialize(
    itunes_matcher: ItunesPreviewMatcher.new,
    youtube_matcher: YoutubeClipMatcher.new,
    feature_extractor: EssentiaFeatureExtractor.new(models_dir: ENV.fetch("ESSENTIA_MODELS_DIR", Rails.root.join("tmp", "essentia_models"))),
    grounding_tracks_per_album: ENV.fetch("GROUNDING_TRACKS_PER_ALBUM", "4").to_i,
    youtube_match_confidence_threshold: ENV.fetch("YOUTUBE_MATCH_CONFIDENCE_THRESHOLD", "0.72").to_f,
    enable_youtube_grounding: ActiveModel::Type::Boolean.new.cast(ENV.fetch("ENABLE_YOUTUBE_GROUNDING", "true"))
  )
    @itunes_matcher = itunes_matcher
    @youtube_matcher = youtube_matcher
    @feature_extractor = feature_extractor
    @grounding_tracks_per_album = grounding_tracks_per_album
    @youtube_match_confidence_threshold = youtube_match_confidence_threshold
    @enable_youtube_grounding = enable_youtube_grounding
  end

  def ground(album, on_matched: nil)
    matched_once = false
    guarded_callback = lambda do
      next if matched_once

      matched_once = true
      on_matched&.call
    end

    ground_via_itunes(album, guarded_callback) || ground_via_youtube(album, guarded_callback) || default_attrs
  end

  private

  def default_attrs
    MoodVector::MOOD_HEADS.index_with { 0.5 }.merge(mood_source: "llm_only", match_confidence: 0.0, spread: {})
  end

  def ground_via_itunes(album, on_matched)
    previews = @itunes_matcher.find_previews(title: album.title, artists: album.artists, max_tracks: @grounding_tracks_per_album)
    return nil if previews.empty?

    on_matched.call

    track_coords = previews.filter_map { |preview| analyze_remote_track(preview.preview_url) }
    return nil if track_coords.empty?

    aggregate(track_coords).merge(mood_source: "essentia_itunes", match_confidence: previews.first.match_confidence)
  end

  def ground_via_youtube(album, on_matched)
    return nil unless @enable_youtube_grounding

    clip_paths = @youtube_matcher.find_clips(
      title: album.title, artists: album.artists,
      confidence_threshold: @youtube_match_confidence_threshold, max_clips: @grounding_tracks_per_album
    )
    return nil if clip_paths.compact.empty?

    on_matched.call

    track_coords = clip_paths.compact.filter_map { |clip_path| analyze_local_track(clip_path) }
    return nil if track_coords.empty?

    aggregate(track_coords).merge(mood_source: "essentia_youtube", match_confidence: 1.0)
  end

  def analyze_remote_track(preview_url)
    dest_path = Rails.root.join("tmp", "vibe_doctor_itunes_#{SecureRandom.hex}.audio")
    response = Faraday.get(preview_url) { |request| request.options.timeout = 15 }
    raise Faraday::Error, "download failed: #{response.status}" unless response.success?

    dest_path.binwrite(response.body)
    @feature_extractor.analyze(dest_path)
  rescue EssentiaFeatureExtractor::Error, Faraday::Error => e
    Rails.logger.warn("iTunes-sourced track analysis failed for '#{preview_url}': #{e.message}")
    nil
  ensure
    File.delete(dest_path) if File.exist?(dest_path)
  end

  def analyze_local_track(clip_path)
    @feature_extractor.analyze(clip_path)
  rescue EssentiaFeatureExtractor::Error => e
    Rails.logger.warn("YouTube-sourced track analysis failed for '#{clip_path}': #{e.message}")
    nil
  ensure
    File.delete(clip_path) if File.exist?(clip_path)
  end

  def aggregate(track_coords)
    means = {}
    spreads = {}
    MoodVector::MOOD_HEADS.each do |head|
      values = track_coords.map { |coords| coords[head] }
      means[head] = (values.sum / values.size.to_f).round(10)
      spreads[head] = values.size > 1 ? population_stddev(values) : 0.0
    end
    means.merge(spread: spreads)
  end

  def population_stddev(values)
    mean = values.sum / values.size.to_f
    variance = values.sum { |value| (value - mean)**2 } / values.size.to_f
    Math.sqrt(variance).round(10)
  end
end
