# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppMetrics do
  describe ".collect" do
    it "sets the account and session gauges from the database" do
      create_list(:user, 2)
      create(:user_session)
      create(:user_session, revoked_at: 1.day.ago)

      described_class.collect

      expect(Yabeda.calendar.users.get).to eq(User.count)
      expect(Yabeda.calendar.active_sessions.get).to eq(1)
    end

    it "sets the job gauges by state" do
      allow(SolidQueue::FailedExecution).to receive(:count).and_return(4)

      described_class.collect

      expect(Yabeda.calendar.jobs.get(state: "failed")).to eq(4)
    end

    # A scrape that raises would mark the whole app as down in Prometheus.
    it "logs a count that fails and still sets the others" do
      allow(User).to receive(:count).and_raise(ActiveRecord::ConnectionNotEstablished, "db down")
      allow(Rails.logger).to receive(:warn)
      create(:user_session)

      expect { described_class.collect }.not_to raise_error

      expect(Rails.logger).to have_received(:warn).with(/could not count users/)
      expect(Yabeda.calendar.active_sessions.get).to eq(1)
    end
  end
end
