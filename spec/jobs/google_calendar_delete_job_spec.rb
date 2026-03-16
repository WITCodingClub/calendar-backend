# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendarDeleteJob do
  describe "queue assignment" do
    it "is assigned to the high queue" do
      expect(described_class.new.queue_name).to eq("high")
    end
  end

  describe "#perform" do
    let(:calendar_id) { "test_calendar_id@group.calendar.google.com" }

    it "calls GoogleCalendarService#delete_calendar with the correct calendar_id" do
      service_double = instance_double(GoogleCalendarService)
      allow(GoogleCalendarService).to receive(:new).and_return(service_double)
      allow(service_double).to receive(:delete_calendar).with(calendar_id)

      described_class.perform_now(calendar_id)

      expect(GoogleCalendarService).to have_received(:new)
      expect(service_double).to have_received(:delete_calendar).with(calendar_id)
    end

    context "when Google Calendar returns 404 Not Found" do
      it "treats the error as success and does not re-raise" do
        service_double = instance_double(GoogleCalendarService)
        allow(GoogleCalendarService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:delete_calendar).with(calendar_id)
                                                          .and_raise(Google::Apis::ClientError.new("notFound: Not Found", status_code: 404))

        expect { described_class.perform_now(calendar_id) }.not_to raise_error
      end
    end

    context "when Google Calendar returns a non-404 client error" do
      it "re-raises the error" do
        service_double = instance_double(GoogleCalendarService)
        allow(GoogleCalendarService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:delete_calendar).with(calendar_id)
                                                          .and_raise(Google::Apis::ClientError.new("forbidden: Forbidden", status_code: 403))

        expect { described_class.perform_now(calendar_id) }.to raise_error(Google::Apis::ClientError)
      end
    end
  end
end
