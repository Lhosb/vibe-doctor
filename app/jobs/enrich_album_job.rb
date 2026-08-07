class EnrichAlbumJob < ApplicationJob
  queue_as :default

  def perform(album, mood_grounder: nil, feature_extractor: nil, vibe_card_generator: nil, embedding_service: nil)
    feature_extractor ||= MoodProbe::Extractor.new(
      models_dir: ENV.fetch("ESSENTIA_MODELS_DIR", Rails.root.join("tmp", "essentia_models"))
    )
    feature_extractor.verify!
    mood_grounder ||= MoodGroundingService.new(feature_extractor:)
    vibe_card_generator ||= VibeCardGenerator.new
    embedding_service ||= AlbumEmbeddingService.new

    album.start_matching!

    extraction_started = false
    on_matched = lambda do
      next if extraction_started

      extraction_started = true
      album.start_extracting!
    end

    mood_attrs = mood_grounder.ground(album, on_matched: on_matched)
    album.start_extracting! unless extraction_started
    mood_vector = album.mood_vector || album.build_mood_vector
    mood_vector.update!(mood_attrs)

    card_schema = vibe_card_generator.generate(album)
    vibe_card = album.vibe_card || album.build_vibe_card
    if card_schema
      vibe_card.update!(
        time_of_day: card_schema.time_of_day, activities: card_schema.activities,
        energy_arc: card_schema.energy_arc, texture: card_schema.texture,
        seasons: card_schema.seasons, prose: card_schema.prose
      )
    else
      vibe_card.save!
    end

    facet_vectors = embedding_service.embed(album, mood_vector, vibe_card)
    embedding = album.embedding || album.build_embedding
    embedding.update!(facet_vectors)

    album.ground!
  rescue StandardError => e
    Rails.logger.error("EnrichAlbumJob failed for album #{album.id}: #{e.message}")
    begin
      album.fail_enrichment!
    rescue Album::InvalidTransition
      nil
    end
    raise
  end
end
