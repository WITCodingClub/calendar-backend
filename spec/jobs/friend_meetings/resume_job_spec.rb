# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendMeetings::ResumeJob do
  let(:user)      { create(:user) }
  let(:publisher) { instance_double(FriendMeetings::Publisher, resume: nil) }

  it "resumes the person's meeting work" do
    allow(FriendMeetings::Publisher).to receive(:new).with(user).and_return(publisher)

    described_class.perform_now(user)

    expect(publisher).to have_received(:resume)
  end

  it "shares the concurrency key of the course sync for the same person" do
    expect(described_class.new(user).concurrency_key).to eq("GoogleCalendarSyncJob/google_calendar_sync_user_#{user.id}")
  end
end
