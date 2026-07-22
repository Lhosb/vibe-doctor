require "rails_helper"

RSpec.describe TemperatureSampler do
  let(:scored_items) do
    [
      { album: :top, rerank_score: 0.9, rationale: "best" },
      { album: :mid, rerank_score: 0.5, rationale: "ok" },
      { album: :low, rerank_score: 0.1, rationale: "meh" }
    ]
  end

  it "raises when given no items" do
    sampler = described_class.new
    expect { sampler.sample(scored_items: [], temperature: 0.7) }.to raise_error(ArgumentError)
  end

  it "picks the top-scored item when the random draw favors it" do
    sampler = described_class.new(random: instance_double(Random, rand: 0.0))
    result = sampler.sample(scored_items: scored_items, temperature: 0.7)
    expect(result[:album]).to eq(:top)
  end

  it "picks the lowest-scored item when the random draw is at the tail" do
    sampler = described_class.new(random: instance_double(Random, rand: 0.999))
    result = sampler.sample(scored_items: scored_items, temperature: 0.7)
    expect(result[:album]).to eq(:low)
  end
end
