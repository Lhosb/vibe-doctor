Rails.application.config.after_initialize do
  registry = Sonance::Registry.default
  missing_descriptors = MoodVectors::EssentiaMapper::DESCRIPTORS - registry.ids
  if missing_descriptors.any?
    raise "sonance registry is missing mapped descriptors: #{missing_descriptors.join(", ")}"
  end

  %i[valence_emomusic arousal_emomusic].each do |descriptor_id|
    native_range = registry.fetch(descriptor_id).native_range
    next if native_range == MoodVectors::EssentiaMapper::EMOMUSIC_RANGE

    raise "#{descriptor_id} native range #{native_range} does not match mapper range " \
          "#{MoodVectors::EssentiaMapper::EMOMUSIC_RANGE}"
  end
end
