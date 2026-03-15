# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncMeetingTimeJob do
  describe "queue assignment" do
    it "is assigned to the high queue" do
      expect(described_class.new.queue_name).to eq("high")
    end
  end

  describe "#perform" do
    let(:user) { create(:user) }
    let(:meeting_time) { create(:meeting_time) }

    it "calls sync_meeting_time on the user with force: true" do
      allow(User).to receive(:find).with(user.id).and_return(user)
      allow(user).to receive(:sync_meeting_time)

      described_class.perform_now(user.id, meeting_time.id)

      expect(user).to have_received(:sync_meeting_time).with(meeting_time.id, force: true)
    end

    it "raises ActiveRecord::RecordNotFound when the user does not exist" do
      expect {
        described_class.perform_now(-1, meeting_time.id)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
