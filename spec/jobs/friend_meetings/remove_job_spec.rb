# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendMeetings::RemoveJob do
  let(:meeting)   { create(:friend_meeting) }
  let(:publisher) { instance_double(FriendMeetings::Publisher, remove: nil) }

  describe "errors" do
    include ActiveJob::TestHelper

    let(:meeting) { create(:friend_meeting, :cancelled) }

    before { allow(FriendMeetings::Publisher).to receive(:new).and_return(publisher) }

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
