namespace :enrichment do
  desc "Synchronously enrich every album needing enrichment (pending or failed)"
  task backfill: :environment do
    run_enrichment(Album.needing_enrichment.to_a)
  end

  desc "Force every album back through essentia grounding, including ones already " \
       "marked grounded via the llm_only fallback (production ran without a working " \
       "essentia toolchain, so none of them ever got real audio analysis)"
  task reground_all: :environment do
    albums = Album.all.to_a
    albums.each(&:reset_enrichment!)
    run_enrichment(albums)
  end
end

def run_enrichment(albums)
  succeeded = 0
  failed = 0

  albums.each do |album|
    EnrichAlbumJob.perform_now(album)
    succeeded += 1
  rescue StandardError => e
    failed += 1
    message = "Album #{album.id} (#{album.title}) failed: #{e.message}"
    puts message
    Rails.logger.error(message)
  end

  summary = "#{albums.size} albums processed: #{succeeded} succeeded, #{failed} failed"
  puts summary
  Rails.logger.info(summary)
end
