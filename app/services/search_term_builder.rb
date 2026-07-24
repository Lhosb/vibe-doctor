require "set"

module SearchTermBuilder
  module_function

  ARTIST_SUFFIX_PATTERN = /\s*\(\d+\)\s*$/

  # The ladder's first (best-guess) rung. Reused as-is by YoutubeClipMatcher.
  def clean_search_term(title, artists)
    build_ladder(title, artists).first
  end

  def build_ladder(title, artists)
    cleaned_artists = dedupe_preserve_order(artists.map { |artist| strip_artist_suffix(artist) })
    artist_text = cleaned_artists.join(" ")
    ladder = [ "#{artist_text} #{title}".strip, title.strip ]
    ladder.concat(title_variants(title).map { |variant| "#{artist_text} #{variant}".strip })
    dedupe_preserve_order(ladder)
  end

  def strip_artist_suffix(artist)
    artist.gsub(ARTIST_SUFFIX_PATTERN, "").strip
  end

  # Splits dual-language "A = B" titles into [title, A, B]; else just [title].
  def title_variants(title)
    return [ title ] unless title.include?(" = ")

    left, right = title.split(" = ", 2)
    dedupe_preserve_order([ title, left, right ])
  end

  def dedupe_preserve_order(items)
    seen = Set.new
    items.select { |item| seen.add?(item.downcase) }
  end
end
