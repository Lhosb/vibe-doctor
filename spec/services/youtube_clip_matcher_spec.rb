require "rails_helper"

RSpec.describe YoutubeClipMatcher do
  subject(:matcher) { described_class.new }

  it "accepts no constructor parameters, so the executable cannot be injected" do
    expect(described_class.instance_method(:initialize).parameters).to be_empty
  end

  def search_result(id, title)
    "#{{ id: id, title: title }.to_json}\n"
  end

  it "searches with the cleaned artist+title term and downloads clips above the confidence threshold" do
    allow(Open3).to receive(:capture3).with(
      "yt-dlp", "ytsearch3:Whitney Rendez-Vous", "--flat-playlist", "--dump-json",
      "--quiet", "--no-warnings", "--socket-timeout", "30"
    ).and_return([ search_result("abc123", "Whitney - Rendez-Vous (Official Audio)"), "", instance_double(Process::Status, success?: true) ])

    allow(Open3).to receive(:capture3).with(
      "yt-dlp", "https://www.youtube.com/watch?v=abc123", "--format", "bestaudio/best",
      "--download-sections", "*60-105", "--force-keyframes-at-cuts", "--output", instance_of(String),
      "--quiet", "--no-warnings", "--socket-timeout", "30"
    ) do |*args|
      dest_dir = File.dirname(args[args.index("--output") + 1])
      File.write(File.join(dest_dir, "clip.m4a"), "fake audio bytes")
      [ "", "", instance_double(Process::Status, success?: true) ]
    end

    clips = matcher.find_clips(title: "Rendez-Vous", artists: [ "Whitney (8)" ], confidence_threshold: 0.5, max_clips: 3)

    expect(clips.length).to eq(1)
    expect(File.read(clips.first)).to eq("fake audio bytes")
  end

  it "discards results below the confidence threshold without downloading them" do
    allow(Open3).to receive(:capture3).with("yt-dlp", "ytsearch3:Kind of Blue", any_args)
      .and_return([ search_result("xyz", "Completely Unrelated Bootleg"), "", instance_double(Process::Status, success?: true) ])

    expect(Open3).not_to receive(:capture3).with("yt-dlp", "https://www.youtube.com/watch?v=xyz", any_args)

    clips = matcher.find_clips(title: "Kind of Blue", artists: [], confidence_threshold: 0.6, max_clips: 3)

    expect(clips).to eq([])
  end

  it "returns an empty array when the search itself fails" do
    allow(Open3).to receive(:capture3).with("yt-dlp", "ytsearch3:Kind of Blue", any_args)
      .and_return([ "", "network error", instance_double(Process::Status, success?: false) ])

    expect(matcher.find_clips(title: "Kind of Blue", artists: [], confidence_threshold: 0.5, max_clips: 3)).to eq([])
  end

  it "skips a failed download but keeps any others" do
    allow(Open3).to receive(:capture3).with("yt-dlp", "ytsearch3:Kind of Blue", any_args).and_return(
      [
        [ search_result("one", "Kind of Blue Full Album"), search_result("two", "Kind of Blue Full Album") ].join,
        "", instance_double(Process::Status, success?: true)
      ]
    )
    allow(Open3).to receive(:capture3).with("yt-dlp", "https://www.youtube.com/watch?v=one", any_args)
      .and_return([ "", "boom", instance_double(Process::Status, success?: false) ])
    allow(Open3).to receive(:capture3).with("yt-dlp", "https://www.youtube.com/watch?v=two", any_args) do |*args|
      dest_dir = File.dirname(args[args.index("--output") + 1])
      File.write(File.join(dest_dir, "clip.m4a"), "ok")
      [ "", "", instance_double(Process::Status, success?: true) ]
    end

    clips = matcher.find_clips(title: "Kind of Blue", artists: [], confidence_threshold: 0.5, max_clips: 3)

    expect(clips.length).to eq(1)
  end
end
