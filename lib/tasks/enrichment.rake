module EnrichmentRun
  # Five catches a catalogue outage early while tolerating four genuinely unmatchable albums in a row.
  CONSECUTIVE_LLM_ONLY_LIMIT = 5

  class ConsecutiveLlmOnlyError < MoodProbe::FatalError; end
end

namespace :enrichment do
  desc "Synchronously enrich every album needing enrichment (pending or failed)"
  task backfill: :environment do
    run_enrichment(Album.needing_enrichment.to_a)
  end

  desc "Force every album back through essentia grounding, including ones already " \
       "marked grounded via the llm_only fallback (production ran without a working " \
       "essentia toolchain, so none of them ever got real audio analysis)"
  task reground_all: :environment do
    feature_extractor = MoodProbe::Extractor.new(
      models_dir: ENV.fetch("ESSENTIA_MODELS_DIR", Rails.root.join("tmp", "essentia_models"))
    )
    feature_extractor.verify!

    albums = Album.all.to_a
    albums.each(&:reset_enrichment!)
    run_enrichment(albums, feature_extractor:)
  end
end

def run_enrichment(
  albums,
  feature_extractor: MoodProbe::Extractor.new(
    models_dir: ENV.fetch("ESSENTIA_MODELS_DIR", Rails.root.join("tmp", "essentia_models"))
  )
)
  succeeded = 0
  failed = 0
  consecutive_llm_only = 0
  unless ActiveModel::Type::Boolean.new.cast(ENV.fetch("ENABLE_YOUTUBE_GROUNDING", "true"))
    Rails.logger.warn(
      "ENABLE_YOUTUBE_GROUNDING is false; per-album systematic-failure detection is unavailable, " \
      "so the run-level consecutive llm_only guard is the backstop"
    )
  end
  feature_extractor.verify!

  albums.each do |album|
    begin
      EnrichAlbumJob.perform_now(album, feature_extractor:)
    rescue MoodProbe::FatalError
      failed += 1
      raise
    rescue StandardError => e
      failed += 1
      consecutive_llm_only = 0
      message = "Album #{album.id} (#{album.title}) failed: #{e.message}"
      puts message
      Rails.logger.error(message)
    else
      succeeded += 1
      if album.reload.mood_vector&.mood_source == "llm_only"
        consecutive_llm_only += 1
        if consecutive_llm_only >= EnrichmentRun::CONSECUTIVE_LLM_ONLY_LIMIT
          raise EnrichmentRun::ConsecutiveLlmOnlyError,
                "#{consecutive_llm_only} consecutive albums produced llm_only mood vectors"
        end
      else
        consecutive_llm_only = 0
      end
    end
  end
ensure
  summary = "#{albums.size} albums processed: #{succeeded} succeeded, #{failed} failed"
  puts summary
  Rails.logger.info(summary)
end
