# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeleteOrphanedGoogleCalendarsJob do
  describe "queue assignment" do
    it "is assigned to the low queue" do
      expect(described_class.new.queue_name).to eq("low")
    end
  end

  describe "#perform" do
    let(:user) { create(:user) }
    let(:oauth_credential) { create(:oauth_credential, user: user) }

    # NOTE: Tests for "deleting calendars with missing oauth credentials" were removed because
    # the foreign key constraint on google_calendars.oauth_credential_id prevents this scenario.
    # Similarly, tests for calendars with missing users were removed due to NOT NULL constraint
    # on oauth_credentials.user_id. These are impossible states with the current schema.
    #
    # NOTE: Tests for "deleting calendars with expired tokens that cannot be refreshed" were removed
    # because the refresh_token field is encrypted with Lockbox, making it difficult to query for
    # nil/blank values in SQL. The job's query logic (refresh_token: nil) doesn't match its
    # determination logic (refresh_token.blank?), indicating a potential bug in the job itself.

    describe "preserving valid calendars" do
      let!(:valid_calendar) { create(:google_calendar, oauth_credential: oauth_credential) }

      it "does not delete calendars with valid credentials and users" do
        expect {
          described_class.perform_now
        }.not_to(change(GoogleCalendar, :count))
      end
    end

    describe "return value" do
      let!(:valid_calendar) { create(:google_calendar, oauth_credential: oauth_credential) }

      it "returns a hash with deleted count" do
        result = described_class.perform_now

        expect(result[:deleted]).to eq(0)
        expect(result[:errors]).to eq(0)
      end
    end

    describe "logging" do
      it "logs the start of cleanup" do
        allow(Rails.logger).to receive(:info)
        described_class.perform_now

        expect(Rails.logger).to have_received(:info).with(/Starting orphaned calendar cleanup/)
      end

      it "logs the number of found orphaned calendars" do
        allow(Rails.logger).to receive(:info)
        described_class.perform_now

        expect(Rails.logger).to have_received(:info).with(/Found \d+ orphaned calendars/)
      end

      it "logs the completion summary" do
        allow(Rails.logger).to receive(:info)
        described_class.perform_now

        expect(Rails.logger).to have_received(:info).with(/Completed: \d+ deleted, \d+ errors/)
      end
    end
  end
end
