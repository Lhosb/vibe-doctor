module Recommendations
  class TemperatureSampler
    def initialize(random: Random.new)
      @random = random
    end

    def sample(scored_items:, temperature: 0.7)
      raise ArgumentError, "scored_items must not be empty" if scored_items.empty?

      weights = softmax(scored_items.map { |item| item.fetch(:rerank_score) }, temperature)
      scored_items[weighted_sample_index(weights)]
    end

    private

    def softmax(scores, temperature)
      scaled = scores.map { |s| s / temperature }
      max = scaled.max
      exps = scaled.map { |s| Math.exp(s - max) }
      total = exps.sum
      exps.map { |e| e / total }
    end

    def weighted_sample_index(weights)
      target = @random.rand
      cumulative = 0.0
      weights.each_with_index do |weight, index|
        cumulative += weight
        return index if target <= cumulative
      end
      weights.length - 1
    end
  end
end
