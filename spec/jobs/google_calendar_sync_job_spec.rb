# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendarSyncJob do
  describe "queue assignment" do
    it "is assigned to the high queue" do
      expect(described_class.new.queue_name).to eq("high")
    end
  end

  describe "#perform" do
    let(:user) { create(:user) }

    it "calls sync_course_schedule on the user" do
      allow(user).to receive(:sync_course_schedule)

      described_class.perform_now(user)

      expect(user).to have_received(:sync_course_schedule)
    end
  end
end
