require "rails_helper"
require "rake"

RSpec.describe "enrichment:backfill rake task" do
  before(:all) { Rails.application.load_tasks }
  after { Rake::Task["enrichment:backfill"].reenable }

  it "synchronously enriches every album needing enrichment and skips ones that don't" do
    pending = Album.create!(master_id: 1, title: "Pending")
    grounded = Album.create!(master_id: 2, title: "Grounded").tap(&:start_matching!).tap(&:start_extracting!).tap(&:ground!)

    allow(EnrichAlbumJob).to receive(:perform_now)

    Rake::Task["enrichment:backfill"].invoke

    expect(EnrichAlbumJob).to have_received(:perform_now).with(pending).once
    expect(EnrichAlbumJob).not_to have_received(:perform_now).with(grounded)
  end

  it "keeps processing after one album fails, and prints a summary" do
    ok = Album.create!(master_id: 1, title: "Ok")
    broken = Album.create!(master_id: 2, title: "Broken")

    allow(EnrichAlbumJob).to receive(:perform_now) do |album|
      raise "boom" if album == broken
    end

    expect { Rake::Task["enrichment:backfill"].invoke }
      .to output(/2 albums processed.*1 succeeded.*1 failed/m).to_stdout

    expect(EnrichAlbumJob).to have_received(:perform_now).with(ok)
  end

  it "logs the per-album failure and the run summary to Rails.logger" do
    ok = Album.create!(master_id: 1, title: "Ok")
    broken = Album.create!(master_id: 2, title: "Broken")

    allow(EnrichAlbumJob).to receive(:perform_now) do |album|
      raise "boom" if album == broken
    end
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:info)

    Rake::Task["enrichment:backfill"].invoke

    expect(Rails.logger).to have_received(:error).with(/Album #{broken.id} \(Broken\) failed: boom/)
    expect(Rails.logger).to have_received(:info).with(/2 albums processed: 1 succeeded, 1 failed/)
    expect(EnrichAlbumJob).to have_received(:perform_now).with(ok)
  end
end
