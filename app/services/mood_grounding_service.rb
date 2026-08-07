require "securerandom"

class MoodGroundingService
  class SystematicTrackFailure < MoodProbe::FatalError; end

  def initialize(
    itunes_matcher: ItunesPreviewMatcher.new,
    youtube_matcher: YoutubeClipMatcher.new,
    feature_extractor: MoodProbe::Extractor.new(
      models_dir: ENV.fetch("ESSENTIA_MODELS_DIR", Rails.root.join("tmp", "essentia_models"))
    ),
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

    itunes_attrs, itunes_failure = ground_via_itunes(album, guarded_callback)
    return itunes_attrs if itunes_attrs

    youtube_attrs, youtube_failure = ground_via_youtube(album, guarded_callback)
    return youtube_attrs if youtube_attrs

    raise_systematic_track_failure!(itunes_failure, youtube_failure)
    default_attrs
  end

  private

  def default_attrs
    MoodVector::MOOD_HEADS.index_with { 0.5 }.merge(mood_source: "llm_only", match_confidence: 0.0, spread: {})
  end

  def ground_via_itunes(album, on_matched)
    previews = @itunes_matcher.find_previews(title: album.title, artists: album.artists, max_tracks: @grounding_tracks_per_album)
    return [ nil, nil ] if previews.empty?

    on_matched.call

    track_errors = []
    track_coords = previews.filter_map { |preview| analyze_remote_track(preview.preview_url, track_errors:) }
    failure = systematic_track_failure(track_coords, track_errors, previews.size, source: "iTunes")
    return [ nil, failure ] if track_coords.empty?

    [ aggregate(track_coords).merge(mood_source: "essentia_itunes", match_confidence: previews.first.match_confidence), nil ]
  end

  def ground_via_youtube(album, on_matched)
    return [ nil, nil ] unless @enable_youtube_grounding

    clip_paths = @youtube_matcher.find_clips(
      title: album.title, artists: album.artists,
      confidence_threshold: @youtube_match_confidence_threshold, max_clips: @grounding_tracks_per_album
    )
    return [ nil, nil ] if clip_paths.compact.empty?

    on_matched.call

    paths = clip_paths.compact
    begin
      track_errors = []
      track_coords = paths.filter_map { |clip_path| analyze_local_track(clip_path, track_errors:) }
      failure = systematic_track_failure(track_coords, track_errors, paths.size, source: "YouTube")
      return [ nil, failure ] if track_coords.empty?

      [ aggregate(track_coords).merge(mood_source: "essentia_youtube", match_confidence: 1.0), nil ]
    ensure
      paths.each { |path| File.delete(path) if File.exist?(path) }
    end
  end

  def analyze_remote_track(preview_url, track_errors:)
    dest_path = Rails.root.join("tmp", "vibe_doctor_itunes_#{SecureRandom.hex}.audio")
    response = Faraday.get(preview_url) { |request| request.options.timeout = 15 }
    raise Faraday::Error, "download failed: #{response.status}" unless response.success?

    dest_path.binwrite(response.body)
    @feature_extractor.analyze(dest_path).to_h
  rescue MoodProbe::TrackError => e
    track_errors << e
    Rails.logger.warn("iTunes-sourced track analysis failed for '#{preview_url}': #{e.message}")
    nil
  rescue Faraday::Error => e
    track_errors << e
    Rails.logger.warn("iTunes-sourced track analysis failed for '#{preview_url}': #{e.message}")
    nil
  ensure
    File.delete(dest_path) if File.exist?(dest_path)
  end

  def analyze_local_track(clip_path, track_errors:)
    @feature_extractor.analyze(clip_path).to_h
  rescue MoodProbe::TrackError => e
    track_errors << e
    Rails.logger.warn("YouTube-sourced track analysis failed for '#{clip_path}': #{e.message}")
    nil
  ensure
    File.delete(clip_path) if File.exist?(clip_path)
  end

  def systematic_track_failure(track_coords, track_errors, track_count, source:)
    faraday_failures = track_errors.count { |error| error.is_a?(Faraday::Error) }
    analyzable = track_count - faraday_failures
    probe_errors = track_errors.reject { |error| error.is_a?(Faraday::Error) }
    # A single analyzable failure is trivially uniform, so it cannot justify aborting the catalogue.
    return unless analyzable > 1 && track_coords.empty? && probe_errors.size == analyzable

    error_classes = probe_errors.map(&:class).uniq
    # Requiring one class deliberately favors false negatives over escalating unrelated per-track faults.
    return unless error_classes.one?

    error_class = error_classes.first
    # Download failures stay recorded for diagnostics but provide no extractor evidence; the run-level
    # llm_only guard catches download-scale outages across albums regardless of error class.
    "#{analyzable} #{source} tracks failed with #{error_class}"
  end

  def raise_systematic_track_failure!(itunes_failure, youtube_failure)
    return unless itunes_failure && youtube_failure

    # The sources need not share a class; two independent uniform failures are still systematic evidence.
    raise SystematicTrackFailure, "#{itunes_failure}; #{youtube_failure}"
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
