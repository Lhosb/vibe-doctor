namespace :enrichment do
  desc "Synchronously enrich every album needing enrichment (pending or failed)"
  task backfill: :environment do
    albums = Album.needing_enrichment.to_a
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
end
