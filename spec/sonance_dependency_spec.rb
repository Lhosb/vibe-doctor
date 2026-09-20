require "open3"
require "sonance"
require "spec_helper"

RSpec.describe "sonance dependency" do
  it "loads the v0.4.0 release commit" do
    lockfile = Pathname(__dir__).join("../Gemfile.lock").read
    gem_path = Gem.loaded_specs.fetch("sonance").full_gem_path
    revision, status = Open3.capture2("git", "-C", gem_path, "rev-parse", "HEAD")

    expect(Sonance::VERSION).to eq("0.4.0")
    expect(lockfile).to include("remote: https://github.com/Lhosb/sonance.git", "tag: v0.4.0")
    expect(status).to be_success
    expect(revision.chomp).to eq("1115824c8fec533037c35aaf4ec091bb42ac63df")
  end
end
