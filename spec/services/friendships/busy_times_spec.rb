# frozen_string_literal: true

require "rails_helper"

RSpec.describe Friendships::BusyTimes do
  let(:viewer)     { create(:user) }
  let(:friendship) { create(:friendship, :accepted, requester: viewer) }
  let(:from)       { Date.new(2026, 9, 14) }

  it "is not readable for a friend who shares the full schedule while the flag is off" do
    expect(described_class.new(viewer, friendship)).not_to be_readable
  end

  it "reads the busy blocks of the friend, not of the viewer" do
    friendship.update!(addressee_visibility: "availability_only")
    allow(BusyBlocks).to receive(:new).and_call_original

    json = described_class.new(viewer, friendship).as_json(from, from + 6)

    expect(BusyBlocks).to have_received(:new).with(friendship.addressee, from: from, to: from + 6)
    expect(json).to include(:busy, start_date: from.iso8601)
  end
end
