# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendMeetingRemovalSweepJob do
  include ActiveJob::TestHelper

  it "starts the remove job again for each meeting cancelled over an hour ago" do
    stale    = create(:friend_meeting, cancelled_at: 2.hours.ago)
    recent   = create(:friend_meeting, cancelled_at: 5.minutes.ago)
    live     = create(:friend_meeting)
    refused  = create(:friend_meeting, cancelled_at: 2.hours.ago, destinations: %w[google])
    refused.publication_for("google").mark_failed!("MicrosoftGraph::AuthError")

    described_class.perform_now

    expect(FriendMeetingRemoveJob).to have_been_enqueued.with(stale).once
    [ recent, live, refused ].each { |meeting| expect(FriendMeetingRemoveJob).not_to have_been_enqueued.with(meeting) }
  end

  it "runs every hour in production" do
    schedule = YAML.load_file(Rails.root.join("config/recurring.yml")).dig("production", "friend_meeting_removal_sweep")

    expect(schedule).to include("class" => "FriendMeetingRemovalSweepJob", "schedule" => "every hour at minute 27")
  end
end
