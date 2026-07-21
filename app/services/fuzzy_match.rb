module FuzzyMatch
  module_function

  # Mirrors rapidfuzz's fuzz.token_set_ratio: tokenize both strings, then
  # compare the shared-token string against each side's full token string
  # (shared + its own leftovers) and take the best of the three pairings.
  def token_set_ratio(a, b)
    tokens_a = tokenize(a)
    tokens_b = tokenize(b)
    intersection = tokens_a & tokens_b
    diff_a = tokens_a - intersection
    diff_b = tokens_b - intersection

    shared = intersection.sort.join(" ")
    combined_a = diff_a.empty? ? shared : "#{shared} #{diff_a.sort.join(" ")}".strip
    combined_b = diff_b.empty? ? shared : "#{shared} #{diff_b.sort.join(" ")}".strip

    [ratio(shared, combined_a), ratio(shared, combined_b), ratio(combined_a, combined_b)].max
  end

  def tokenize(text)
    text.to_s.downcase.scan(/[a-z0-9]+/).uniq
  end

  # Indel similarity: 2 * longest_common_subsequence / (len(a) + len(b)).
  # This is exactly what rapidfuzz's fuzz.ratio computes (edit distance with
  # only insertions/deletions, normalized to 0..1 instead of a 0..100 score).
  def ratio(a, b)
    return 1.0 if a.empty? && b.empty?

    lcs = longest_common_subsequence_length(a, b)
    (2.0 * lcs) / (a.length + b.length)
  end

  def longest_common_subsequence_length(a, b)
    previous = Array.new(b.length + 1, 0)
    a.each_char do |char_a|
      current = [0]
      b.each_char.with_index do |char_b, j|
        current << (char_a == char_b ? previous[j] + 1 : [current[j], previous[j + 1]].max)
      end
      previous = current
    end
    previous.last
  end
end
