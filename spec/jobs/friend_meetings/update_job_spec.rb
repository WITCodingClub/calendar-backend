# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendMeetings::UpdateJob do
  let(:meeting)   { create(:friend_meeting) }
  let(:publisher) { instance_double(FriendMeetings::Publisher, update: nil) }

  it "runs the publisher for the meeting's owner" do
    allow(FriendMeetings::Publisher).to receive(:new).with(meeting.user).and_return(publisher)

    described_class.perform_now(meeting)

    expect(publisher).to have_received(:update).with(meeting)
  end

  it "shares the concurrency key of the course sync for the same person" do
    job = described_class.new(meeting)

    expect(job.concurrency_key).to eq("GoogleCalendarSyncJob/google_calendar_sync_user_#{meeting.user_id}")
  end
end
