require "mood_probe"
require "spec_helper"

RSpec.describe "mood_probe dependency" do
  it "loads the v0.2.0 release commit" do
    lockfile = Pathname(__dir__).join("../Gemfile.lock").read

    expect(MoodProbe::VERSION).to eq("0.2.0")
    expect(lockfile).to include("revision: 848f6894a6022b5a32ae2b6b0c6898ac84986fa0")
  end
end
