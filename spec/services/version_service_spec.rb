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
end
