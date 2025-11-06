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

    describe "deleting calendars with missing oauth credentials" do
      let!(:orphaned_calendar) do
        calendar = create(:google_calendar, oauth_credential: oauth_credential)
        oauth_credential.destroy!
        calendar.reload
        calendar
      end

      it "deletes calendars with missing oauth credentials" do
        expect {
          described_class.perform_now
        }.to change(GoogleCalendar, :count).by(-1)
      end

      it "logs the deletion" do
        allow(Rails.logger).to receive(:info)
        described_class.perform_now

        expect(Rails.logger).to have_received(:info).with(/Deleting calendar.*Missing OAuth credential/)
      end
    end

    describe "deleting calendars with expired tokens that cannot be refreshed" do
      let(:expired_credential) do
        create(:oauth_credential,
               user: user,
               token_expires_at: 1.day.ago,
               refresh_token: nil)
      end
      let!(:orphaned_calendar) { create(:google_calendar, oauth_credential: expired_credential) }

      it "deletes calendars with expired non-refreshable tokens" do
        expect {
          described_class.perform_now
        }.to change(GoogleCalendar, :count).by(-1)
      end

      it "logs the deletion with reason" do
        allow(Rails.logger).to receive(:info)
        described_class.perform_now

        expect(Rails.logger).to have_received(:info).with(/Expired token without refresh capability/)
      end
    end

    describe "deleting calendars whose oauth credential has no user" do
      let(:credential_without_user) do
        credential = create(:oauth_credential, user: user)
        user.destroy!
        credential.reload
        credential
      end
      let!(:orphaned_calendar) { create(:google_calendar, oauth_credential: credential_without_user) }

      it "deletes calendars whose user is missing" do
        expect {
          described_class.perform_now
        }.to change(GoogleCalendar, :count).by(-1)
      end

      it "logs the deletion with reason" do
        allow(Rails.logger).to receive(:info)
        described_class.perform_now

        expect(Rails.logger).to have_received(:info).with(/Missing user/)
      end
    end

    describe "preserving valid calendars" do
      let!(:valid_calendar) { create(:google_calendar, oauth_credential: oauth_credential) }

      it "does not delete calendars with valid credentials and users" do
        expect {
          described_class.perform_now
        }.not_to(change(GoogleCalendar, :count))
      end
    end

    describe "error handling" do
      let!(:orphaned_calendar) do
        calendar = create(:google_calendar, oauth_credential: oauth_credential)
        oauth_credential.destroy!
        calendar.reload
        calendar
      end

      it "continues processing other calendars if one fails" do
        allow(orphaned_calendar).to receive(:destroy!).and_raise(StandardError.new("Test error"))
        allow(GoogleCalendar).to receive(:left_joins).and_return(double(where: [orphaned_calendar]))

        expect {
          described_class.perform_now
        }.not_to raise_error
      end

      it "logs errors for failed deletions" do
        allow_any_instance_of(GoogleCalendar).to receive(:destroy!).and_raise(StandardError.new("Test error"))
        allow(Rails.logger).to receive(:error)

        described_class.perform_now

        expect(Rails.logger).to have_received(:error).with(/Failed to delete calendar/)
      end
    end

    describe "return value" do
      let!(:orphaned_calendar1) do
        calendar = create(:google_calendar, oauth_credential: oauth_credential)
        oauth_credential.destroy!
        calendar.reload
        calendar
      end

      let!(:orphaned_calendar2) do
        credential = create(:oauth_credential,
                            user: user,
                            token_expires_at: 1.day.ago,
                            refresh_token: nil)
        create(:google_calendar, oauth_credential: credential)
      end

      it "returns a hash with deleted count" do
        result = described_class.perform_now

        expect(result[:deleted]).to eq(2)
        expect(result[:errors]).to eq(0)
      end

      it "returns error count when deletions fail" do
        allow_any_instance_of(GoogleCalendar).to receive(:destroy!).and_raise(StandardError.new("Test error"))

        result = described_class.perform_now

        expect(result[:deleted]).to eq(0)
        expect(result[:errors]).to be > 0
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
