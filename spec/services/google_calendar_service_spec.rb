# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendarService do
  let(:service) { described_class.new }

  let(:event_data) do
    {
      summary: "Fall Break",
      start_time: Time.zone.local(2026, 10, 12),
      end_time: Time.zone.local(2026, 10, 12, 23, 59, 59),
      all_day: true
    }
  end

  describe "#build_google_event reminders" do
    it "sends the reminder the preferences resolved" do
      google_event = service.send(
        :build_google_event,
        event_data.merge(reminder_settings: [ { "time" => "15", "type" => "hours", "method" => "popup" } ])
      )

      expect(google_event.reminders.use_default).to be(false)
      expect(google_event.reminders.overrides.map(&:minutes)).to eq([ 900 ])
    end

    it "clears the reminders when the list is empty, rather than falling back to the Google defaults" do
      google_event = service.send(:build_google_event, event_data.merge(reminder_settings: []))

      expect(google_event.reminders.use_default).to be(false)
      expect(google_event.reminders.overrides).to eq([])
    end

    it "leaves the Google defaults alone when no reminders were resolved" do
      google_event = service.send(:build_google_event, event_data)

      expect(google_event.reminders).to be_nil
    end
  end

  describe "#update_event_in_calendar" do
    let(:user) { create(:user) }
    let(:service) { described_class.new(user) }
    let(:calendar_api) { instance_double(Google::Apis::CalendarV3::CalendarService) }
    let(:google_calendar) { instance_double(GoogleCalendar, google_calendar_id: "cal@group.calendar.google.com") }
    let(:db_event) { instance_double(GoogleCalendarEvent, google_event_id: "evt123", update!: true) }
    let(:event_with_prefs) do
      event_data.merge(summary: "MATH-1876-03 Calculus 2A", location: "Beatty Hall 420", meeting_time_id: 42)
    end

    it "sends the event it was given, without resolving the preferences again" do
      allow(service).to receive(:resolve_syncable)
      allow(calendar_api).to receive(:update_event)

      result = service.send(:update_event_in_calendar, calendar_api, google_calendar, db_event, event_with_prefs, force: true)

      expect(result).to eq(:updated)
      expect(service).not_to have_received(:resolve_syncable)
      expect(calendar_api).to have_received(:update_event).with(
        "cal@group.calendar.google.com", "evt123",
        having_attributes(summary: "MATH-1876-03 Calculus 2A", location: "Beatty Hall 420")
      )
      expect(db_event).to have_received(:update!).with(hash_including(summary: "MATH-1876-03 Calculus 2A"))
    end
  end

  describe "#remove_calendar_from_user_list_for_email" do
    let(:user) { create(:user) }
    let(:credential) do
      create(:oauth_credential, user: user, email: "second@example.test",
                                access_token: "synthetic-second-token",
                                refresh_token: "synthetic-second-refresh",
                                token_expires_at: 1.hour.from_now)
    end

    before { create(:google_calendar, oauth_credential: credential, google_calendar_id: "synthetic-course-calendar") }

    # OauthCredential calls this when an account is disconnected. While it was
    # private, the call raised NoMethodError and the calendar stayed in the list.
    it "can be called from outside the service" do
      removal = stub_request(:delete, google_calendar_list_url("synthetic-course-calendar"))
        .with(headers: { "Authorization" => "Bearer synthetic-second-token" })
        .to_return(status: 204)

      described_class.new(user).remove_calendar_from_user_list_for_email("synthetic-course-calendar", "second@example.test")

      expect(removal).to have_been_requested.once
    end
  end

  describe "#unshare_calendar_with_email" do
    before { stub_google_service_account }

    it "deletes the ACL rule that shares the calendar with the email" do
      removal = stub_request(:delete, google_acl_url("synthetic-course-calendar", "second@example.test"))
        .with(headers: { "Authorization" => "Bearer synthetic-service-account-token" })
        .to_return(status: 204)

      described_class.new.unshare_calendar_with_email("synthetic-course-calendar", "second@example.test")

      expect(removal).to have_been_requested.once
    end

    it "treats a rule that is already gone as done" do
      stub_request(:delete, google_acl_url("synthetic-course-calendar", "second@example.test"))
        .to_return(status: 404, body: { error: { code: 404, message: "Not Found" } }.to_json,
                   headers: { "Content-Type" => "application/json" })

      expect { described_class.new.unshare_calendar_with_email("synthetic-course-calendar", "second@example.test") }
        .not_to raise_error
    end
  end
end
