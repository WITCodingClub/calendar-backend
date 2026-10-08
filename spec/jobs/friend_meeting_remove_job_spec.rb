# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendMeetingRemoveJob do
  let(:meeting)   { create(:friend_meeting) }
  let(:publisher) { instance_double(FriendMeetingPublisher, remove: nil) }

  it "runs the publisher for the meeting's owner" do
    meeting.update!(cancelled_at: Time.current)
    allow(FriendMeetingPublisher).to receive(:new).with(meeting.user).and_return(publisher)

    described_class.perform_now(meeting)

    expect(publisher).to have_received(:remove).with(meeting)
  end

  it "shares the concurrency key of the course sync for the same person" do
    job = described_class.new(meeting)

    expect(job.concurrency_key).to eq("GoogleCalendarSyncJob/google_calendar_sync_user_#{meeting.user_id}")
  end

  describe "errors" do
    include ActiveJob::TestHelper

    let(:meeting) { create(:friend_meeting, :cancelled) }

    before { allow(FriendMeetingPublisher).to receive(:new).and_return(publisher) }

    [
      Google::Apis::TransmissionError.new("synthetic"),
      Google::Apis::ClientError.new("synthetic", status_code: 403),
      Google::Apis::ServerError.new("synthetic"),
      MicrosoftGraph::Error.new("synthetic")
    ].each do |error|
      it "retries #{error.class.name} later" do
        allow(publisher).to receive(:remove).and_raise(error)

        expect { described_class.perform_now(meeting) }.to have_enqueued_job(described_class).with(meeting)
      end
    end

    it "does nothing for a meeting that is not cancelled" do
      meeting.update!(cancelled_at: nil)

      described_class.perform_now(meeting)

      expect(publisher).not_to have_received(:remove)
    end
  end
end
