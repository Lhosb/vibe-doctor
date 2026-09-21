require "open3"
require "sonance"
require "spec_helper"

RSpec.describe "sonance dependency" do
  it "loads the v0.4.1 release commit" do
    lockfile = Pathname(__dir__).join("../Gemfile.lock").read
    gem_path = Gem.loaded_specs.fetch("sonance").full_gem_path
    # This resolves the release commit. Gemfile.lock records the annotated tag object's SHA,
    # so do not compare this value with its revision line.
    revision, status = Open3.capture2("git", "-C", gem_path, "rev-parse", "HEAD")

    expect(Sonance::VERSION).to eq("0.4.1")
    expect(lockfile).to include("remote: https://github.com/Lhosb/sonance.git", "tag: v0.4.1")
    expect(status).to be_success
    expect(revision.chomp).to eq("dc9a4aedf741aa37f6c791b2ddf9782782b5e55d")
  end
end
