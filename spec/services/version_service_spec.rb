# frozen_string_literal: true

require "rails_helper"

RSpec.describe VersionService do
  before do
    stub_request(:get, %r{\Ahttps://api\.github\.com/repos/WITCodingClub/calendar/})
      .to_return(status: 404, body: "")
    described_class.instance_variable_set(:@current_version, nil)
    described_class.instance_variable_set(:@current_sha, nil)
  end

  after do
    described_class.instance_variable_set(:@current_version, nil)
    described_class.instance_variable_set(:@current_sha, nil)
  end

  # The admin layout renders the version on every page. Starting git for each
  # page forked a process per request.
  it "starts git once per process, not once per call" do
    allow(described_class).to receive(:`).with(/git describe/).and_return("v1.2.3\n")
    allow(described_class).to receive(:`).with(/git rev-parse/).and_return("abc1234\n")

    3.times { described_class.call }

    expect(described_class).to have_received(:`).with(/git describe/).once
    expect(described_class).to have_received(:`).with(/git rev-parse/).once
    expect(described_class.call).to include(current: "v1.2.3", current_sha: "abc1234")
  end

  # The production image has no git binary. The build writes the commit to REVISION.
  context "with a REVISION file and no git" do
    let(:root) { Pathname.new(Dir.mktmpdir) }

    before do
      File.write(root.join("REVISION"), "0123456789abcdef\n")
      allow(Rails).to receive(:root).and_return(root)
      allow(described_class).to receive(:`).and_return("")
    end

    after { FileUtils.remove_entry(root) }

    it "reads the short SHA from REVISION" do
      expect(described_class.current_sha).to eq("0123456")
    end

    it "ignores a blank REVISION file" do
      File.write(root.join("REVISION"), "\n")

      expect(described_class.current_sha).to eq("unknown")
    end

    it "uses the SHA as the version and reports no update" do
      allow_any_instance_of(described_class).to receive(:latest_version).and_return("v6.3.0") # rubocop:disable RSpec/AnyInstance
      result = described_class.call

      expect(result).to include(current: "0123456", update_available: false)
    end
  end
end
