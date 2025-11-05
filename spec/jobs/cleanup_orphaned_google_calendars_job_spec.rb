# frozen_string_literal: true

require "rails_helper"

RSpec.describe CleanupOrphanedGoogleCalendarsJob do
  describe "queue assignment" do
    it "is assigned to the low queue" do
      expect(described_class.new.queue_name).to eq("low")
    end
  end

  describe "#perform" do
    let(:service) { instance_double(GoogleCalendarService) }
    let(:calendar_list) { double(items: [google_calendar]) }
    let(:google_calendar) { double(id: "orphaned_cal_id@group.calendar.google.com", summary: "Orphaned Calendar") }

    before do
      allow(GoogleCalendarService).to receive(:new).and_return(service)
      allow(service).to receive(:list_calendars).and_return(calendar_list)
    end

    context "when there are orphaned calendars in Google" do
      before do
        allow(GoogleCalendar).to receive(:pluck).with(:google_calendar_id).and_return([])
      end

      it "deletes orphaned calendars from Google" do
        allow(service).to receive(:delete_calendar).with(google_calendar.id)

        result = described_class.perform_now

        expect(service).to have_received(:delete_calendar).with(google_calendar.id)
        expect(result[:deleted]).to eq(1)
        expect(result[:errors]).to eq(0)
      end

      it "handles 404 errors gracefully" do
        allow(service).to receive(:delete_calendar)
          .with(google_calendar.id)
          .and_raise(Google::Apis::ClientError.new("Not found", status_code: 404))

        result = described_class.perform_now

        expect(result[:skipped]).to eq(1)
        expect(result[:errors]).to eq(0)
      end

      it "logs other Google API errors" do
        allow(service).to receive(:delete_calendar)
          .with(google_calendar.id)
          .and_raise(Google::Apis::ClientError.new("Bad request", status_code: 400))

        result = described_class.perform_now

        expect(result[:errors]).to eq(1)
        expect(result[:deleted]).to eq(0)
      end
    end

    context "when all Google calendars exist in the database" do
      before do
        allow(GoogleCalendar).to receive(:pluck)
          .with(:google_calendar_id)
          .and_return([google_calendar.id])
        allow(service).to receive(:delete_calendar)
      end

      it "does not delete any calendars" do
        result = described_class.perform_now

        expect(service).not_to have_received(:delete_calendar)
        expect(result[:deleted]).to eq(0)
      end
    end
  end
end
