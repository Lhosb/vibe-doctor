module MoodDescriptor
  module_function

  def render(mood_vector)
    return "" if mood_vector.mood_source == "llm_only"

    phrases = []
    phrases << valence_phrase(mood_vector.valence)
    phrases << arousal_phrase(mood_vector.arousal)
    phrases << "danceable groove" if mood_vector.danceability >= 0.6
    phrases << "acoustic character" if mood_vector.mood_acoustic >= 0.6
    phrases << "relaxed, easygoing feel" if mood_vector.mood_relaxed >= 0.6
    phrases << "cheerful tone" if mood_vector.mood_happy >= 0.6
    phrases.compact.join(", ")
  end

  def valence_phrase(valence)
    return "upbeat, positive mood" if valence >= 0.6
    "melancholic or somber mood" if valence <= 0.4
  end

  def arousal_phrase(arousal)
    return "high energy" if arousal >= 0.6
    "mellow, low-key energy" if arousal <= 0.4
  end
end
