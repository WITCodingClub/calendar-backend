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
end
