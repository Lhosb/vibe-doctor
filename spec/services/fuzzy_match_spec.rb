require "rails_helper"

RSpec.describe FuzzyMatch do
  describe ".token_set_ratio" do
    it "returns 1.0 when one string's tokens are a subset of the other's" do
      expect(described_class.token_set_ratio("Kind of Blue", "Kind of Blue (Legacy Edition)")).to eq(1.0)
    end

    it "returns a low ratio for tokens that share no words" do
      expect(described_class.token_set_ratio("Miles Davis", "John Coltrane").round(2)).to eq(0.17)
    end

    it "returns a partial ratio for a plausible but wrong match" do
      expect(described_class.token_set_ratio("Kind of Blue", "Completely Unrelated Bootleg").round(2)).to eq(0.3)
    end

    it "is case-insensitive" do
      expect(described_class.token_set_ratio("KIND OF BLUE", "kind of blue")).to eq(1.0)
    end
  end
end
