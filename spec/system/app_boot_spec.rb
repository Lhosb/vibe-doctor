require "rails_helper"

RSpec.describe "Application boot" do
  it "loads the Rails environment" do
    expect(Rails.application.class.name).to eq("VibeDoctor::Application")
  end

  it "has the pgvector extension enabled" do
    extensions = ActiveRecord::Base.connection.execute(
      "SELECT extname FROM pg_extension WHERE extname = 'vector'"
    )

    expect(extensions.count).to eq(1)
  end
end
