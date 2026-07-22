require "rails_helper"

RSpec.describe VibeCardGenerator do
  let(:album) { Album.create!(master_id: 1, title: "Kind of Blue", artists: ["Miles Davis"], year: 1959, genres: ["Jazz"], styles: ["Modal"]) }
  let(:parsed_card) do
    VibeCardGenerator::Schema.new(
      time_of_day: ["evening", "late night"], activities: ["winding down", "reading"],
      energy_arc: "Opens hushed, gradually loosens.", texture: "Warm, close-mic'd horns.",
      seasons: ["autumn", "winter"], prose: "A record for slow evenings."
    )
  end
  let(:fake_content_item) { Struct.new(:type, :parsed).new(:output_text, parsed_card) }
  let(:fake_output_item) { Struct.new(:type, :content).new(:message, [fake_content_item]) }
  let(:fake_response) { Struct.new(:output).new([fake_output_item]) }
  let(:client) { double("OpenAI::Client") } # rubocop:disable RSpec/VerifiedDoubles

  subject(:generator) { described_class.new(client: client) }

  before do
    allow(client).to receive_message_chain(:responses, :create).and_return(fake_response)
  end

  it "returns the parsed schema instance" do
    expect(generator.generate(album)).to eq(parsed_card)
  end

  it "sends the system prompt, the schema, and an album description built from title/artist/year/genres/styles" do
    responses = double("responses")
    allow(client).to receive(:responses).and_return(responses)
    expect(responses).to receive(:create) do |**kwargs|
      expect(kwargs[:model]).to eq("gpt-4o-mini")
      expect(kwargs[:text]).to eq(VibeCardGenerator::Schema)
      expect(kwargs[:max_output_tokens]).to eq(300)
      expect(kwargs[:input][0][:content]).to include("Ground every claim")
      expect(kwargs[:input][1][:content]).to eq("Album: Kind of Blue by Miles Davis (1959) genres: Jazz styles: Modal")
      fake_response
    end

    generator.generate(album)
  end

  it "returns nil when the client raises" do
    allow(client).to receive(:responses).and_raise(StandardError, "api down")

    expect(generator.generate(album)).to be_nil
  end

  it "returns nil when the response has no parsed message content" do
    empty_response = Struct.new(:output).new([])
    allow(client).to receive_message_chain(:responses, :create).and_return(empty_response)

    expect(generator.generate(album)).to be_nil
  end
end
