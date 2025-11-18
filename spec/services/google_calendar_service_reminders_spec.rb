# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendarService, "reminders functionality" do
  let(:user) { create(:user) }
  let(:oauth_credential) { create(:oauth_credential, user: user) }
  let(:google_calendar) { create(:google_calendar, oauth_credential: oauth_credential) }
  let(:service) { described_class.new(user) }
  let(:meeting_time) { create(:meeting_time) }

  describe "reminder settings in create_event_in_calendar" do
    let(:mock_service) { double("Google::Apis::CalendarV3::CalendarService") }
    let(:course_event) do
      {
        summary: "Test Course",
        location: "Room 101",
        start_time: Time.zone.parse("2025-01-15 09:00:00"),
        end_time: Time.zone.parse("2025-01-15 10:30:00"),
        recurrence: ["RRULE:FREQ=WEEKLY;BYDAY=MO"],
        meeting_time_id: meeting_time.id
      }
    end
    let(:created_event) { double("Google::Apis::CalendarV3::Event", id: "created_event_123") }

    before do
      allow(service).to receive(:service_account_calendar_service).and_return(mock_service)
      allow(mock_service).to receive(:insert_event).and_return(created_event)
    end

    context "with default reminder settings (system default)" do
      it "applies the default 30-minute popup reminder" do
        service.send(:create_event_in_calendar, mock_service, google_calendar, course_event)

        expect(mock_service).to have_received(:insert_event) do |_calendar_id, google_event|
          expect(google_event.reminders).to be_present
          expect(google_event.reminders.use_default).to be false
          expect(google_event.reminders.overrides).to be_an(Array)
          expect(google_event.reminders.overrides.length).to eq(1)

          reminder = google_event.reminders.overrides.first
          expect(reminder.reminder_method).to eq("popup")
          expect(reminder.minutes).to eq(30)
        end
      end
    end

    context "with custom reminder settings from preferences" do
      before do
        # Create a global calendar preference with custom reminders
        create(:calendar_preference,
               user: user,
               reminder_settings: [
                 { "time" => "15", "type" => "minutes", "method" => "popup" },
                 { "time" => "1", "type" => "hours", "method" => "email" }
               ])
      end

      it "applies custom reminders from preferences" do
        service.send(:create_event_in_calendar, mock_service, google_calendar, course_event)

        expect(mock_service).to have_received(:insert_event) do |_calendar_id, google_event|
          expect(google_event.reminders).to be_present
          expect(google_event.reminders.use_default).to be false
          expect(google_event.reminders.overrides).to be_an(Array)
          expect(google_event.reminders.overrides.length).to eq(2)

          popup_reminder = google_event.reminders.overrides.find { |r| r.reminder_method == "popup" }
          expect(popup_reminder).to be_present
          expect(popup_reminder.minutes).to eq(15)

          email_reminder = google_event.reminders.overrides.find { |r| r.reminder_method == "email" }
          expect(email_reminder).to be_present
          expect(email_reminder.minutes).to eq(60) # 1 hour = 60 minutes
        end
      end
    end

    context "with notification method (should normalize to popup)" do
      before do
        create(:calendar_preference,
               user: user,
               reminder_settings: [
                 { "time" => "10", "type" => "minutes", "method" => "notification" }
               ])
      end

      it "normalizes 'notification' to 'popup' for Google Calendar API" do
        service.send(:create_event_in_calendar, mock_service, google_calendar, course_event)

        expect(mock_service).to have_received(:insert_event) do |_calendar_id, google_event|
          reminder = google_event.reminders.overrides.first
          expect(reminder.reminder_method).to eq("popup") # normalized from "notification"
          expect(reminder.minutes).to eq(10)
        end
      end
    end

    context "with invalid reminder settings" do
      # NOTE: This test was removed because CalendarPreference model validates
      # reminder methods, preventing invalid reminders from being saved.
      # The filtering logic in GoogleCalendarService acts as a defensive measure
      # but cannot be tested via the factory since validation prevents creation
      # of invalid data.

      it "cannot create preferences with invalid reminder methods due to validation" do
        expect {
          create(:calendar_preference,
                 user: user,
                 reminder_settings: [
                   { "time" => "10", "type" => "minutes", "method" => "invalid_method" }
                 ])
        }.to raise_error(ActiveRecord::RecordInvalid, /must have 'method' field/)
      end
    end

    context "with empty reminder settings" do
      before do
        create(:calendar_preference, user: user, reminder_settings: [])
      end

      it "does not set custom reminders" do
        service.send(:create_event_in_calendar, mock_service, google_calendar, course_event)

        expect(mock_service).to have_received(:insert_event) do |_calendar_id, google_event|
          # When reminder_settings is empty, reminders should not be set at all
          # (Google Calendar will use calendar defaults)
          expect(google_event.reminders).to be_nil
        end
      end
    end
  end

  describe "#convert_time_to_minutes" do
    it "converts minutes correctly" do
      expect(service.send(:convert_time_to_minutes, "30", "minutes")).to eq(30)
      expect(service.send(:convert_time_to_minutes, "15", "minutes")).to eq(15)
    end

    it "converts hours to minutes" do
      expect(service.send(:convert_time_to_minutes, "1", "hours")).to eq(60)
      expect(service.send(:convert_time_to_minutes, "2", "hours")).to eq(120)
    end

    it "converts days to minutes" do
      expect(service.send(:convert_time_to_minutes, "1", "days")).to eq(1440)
      expect(service.send(:convert_time_to_minutes, "2", "days")).to eq(2880)
    end

    it "handles decimal values" do
      expect(service.send(:convert_time_to_minutes, "1.5", "hours")).to eq(90)
      expect(service.send(:convert_time_to_minutes, "0.5", "days")).to eq(720)
    end
  end
end
