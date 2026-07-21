require "rails_helper"

RSpec.describe SearchTermBuilder do
  describe ".strip_artist_suffix" do
    it "strips a Discogs disambiguation suffix" do
      expect(described_class.strip_artist_suffix("Whitney (8)")).to eq("Whitney")
    end

    it "leaves an artist with no suffix unchanged" do
      expect(described_class.strip_artist_suffix("Nirvana")).to eq("Nirvana")
    end
  end

  describe ".clean_search_term" do
    it "combines the cleaned artist and title as the first ladder rung" do
      expect(described_class.clean_search_term("Rendez-Vous", ["Whitney (8)"])).to eq("Whitney Rendez-Vous")
    end
  end

  describe ".build_ladder" do
    it "builds artist+title, title-only, and dual-language variant rungs" do
      expect(described_class.build_ladder("Rendez-Vous = Rendezvous", ["Whitney"])).to eq(
        ["Whitney Rendez-Vous = Rendezvous", "Rendez-Vous = Rendezvous", "Whitney Rendez-Vous", "Whitney Rendezvous"]
      )
    end

    it "has just two rungs for a plain single-language title" do
      expect(described_class.build_ladder("Nevermind", ["Nirvana"])).to eq(["Nirvana Nevermind", "Nevermind"])
    end
  end
end
