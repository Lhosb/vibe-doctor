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
    run_enrichment(albums, feature_extractor:, verify: false)
  end
end

def run_enrichment(
  albums,
  feature_extractor: MoodProbe::Extractor.new(
    models_dir: ENV.fetch("ESSENTIA_MODELS_DIR", Rails.root.join("tmp", "essentia_models"))
  ),
  verify: true
)
  succeeded = 0
  failed = 0
  feature_extractor.verify! if verify

  albums.each do |album|
    EnrichAlbumJob.perform_now(album, feature_extractor:)
    succeeded += 1
  rescue MoodProbe::FatalError
    raise
  rescue StandardError => e
    failed += 1
    message = "Album #{album.id} (#{album.title}) failed: #{e.message}"
    puts message
    Rails.logger.error(message)
  end
ensure
  summary = "#{albums.size} albums processed: #{succeeded} succeeded, #{failed} failed"
  puts summary
  Rails.logger.info(summary)
end
