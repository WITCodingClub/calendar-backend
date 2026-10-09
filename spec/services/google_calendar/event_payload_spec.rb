# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendar::EventPayload do
  let(:zone) { Time.find_zone!("America/New_York") }
  let(:event_data) do
    {
      summary: "Fall Break",
      start_time: Time.zone.local(2026, 10, 12),
      end_time: Time.zone.local(2026, 10, 12, 23, 59, 59),
      all_day: true
    }
  end

  describe ".build" do
    it "copies the summary, description, and location" do
      google_event = described_class.build(event_data.merge(description: "Synthetic notes", location: "Synthetic Hall"))

      expect(google_event).to have_attributes(summary: "Fall Break", description: "Synthetic notes", location: "Synthetic Hall")
    end

    it "sends an all-day event as dates, with an end date after the last day" do
      google_event = described_class.build(event_data)

      expect(google_event.start).to eq(date: "2026-10-12")
      expect(google_event.end).to eq(date: "2026-10-13")
    end

    it "sends a timed event in Eastern time" do
      timed = { summary: "Synthetic Lecture", start_time: zone.local(2026, 9, 15, 10), end_time: zone.local(2026, 9, 15, 11, 30) }

      google_event = described_class.build(timed)

      expect(google_event.start).to eq(date_time: "2026-09-15T10:00:00-04:00", time_zone: "America/New_York")
      expect(google_event.end).to eq(date_time: "2026-09-15T11:30:00-04:00", time_zone: "America/New_York")
    end

    it "sends the recurrence and the visibility when they are present" do
      google_event = described_class.build(event_data.merge(recurrence: [ "RRULE:FREQ=WEEKLY;BYDAY=TU" ], visibility: "private"))

      expect(google_event.recurrence).to eq([ "RRULE:FREQ=WEEKLY;BYDAY=TU" ])
      expect(google_event.visibility).to eq("private")
    end

    it "leaves the recurrence and the visibility out when they are blank" do
      google_event = described_class.build(event_data.merge(recurrence: [], visibility: ""))

      expect(google_event.recurrence).to be_nil
      expect(google_event.visibility).to be_nil
    end
  end

  describe ".build reminders" do
    it "sends the reminder the preferences resolved" do
      google_event = described_class.build(
        event_data.merge(reminder_settings: [ { "time" => "15", "type" => "hours", "method" => "popup" } ])
      )

      expect(google_event.reminders.use_default).to be(false)
      expect(google_event.reminders.overrides.map(&:minutes)).to eq([ 900 ])
    end

    it "clears the reminders when the list is empty, rather than falling back to the Google defaults" do
      google_event = described_class.build(event_data.merge(reminder_settings: []))

      expect(google_event.reminders.use_default).to be(false)
      expect(google_event.reminders.overrides).to eq([])
    end

    it "leaves the Google defaults alone when no reminders were resolved" do
      google_event = described_class.build(event_data)

      expect(google_event.reminders).to be_nil
    end

    it "sends a notification as a popup and converts days and minutes" do
      google_event = described_class.build(event_data.merge(reminder_settings: [
        { "time" => "1", "type" => "days", "method" => "notification" },
        { "time" => "30", "type" => "minutes", "method" => "email" }
      ]))

      expect(google_event.reminders.overrides.map { |r| [ r.reminder_method, r.minutes ] }).to eq([ [ "popup", 1440 ], [ "email", 30 ] ])
    end

    it "drops a reminder with an unknown method or a missing field" do
      google_event = described_class.build(event_data.merge(reminder_settings: [
        { "time" => "10", "type" => "minutes", "method" => "sms" },
        { "time" => "10", "method" => "popup" },
        "not a hash"
      ]))

      expect(google_event.reminders.overrides).to eq([])
    end
  end

  describe ".build colors" do
    let(:labels) { instance_double(GoogleCalendar::EventLabels, available?: true, label_id_for: "11111111-2222-3333-4444-555555555555") }

    it "gives a custom color through the label for that color" do
      google_event = described_class.build(event_data.merge(color_id: "#1a2b3c"), labels)

      expect(labels).to have_received(:label_id_for).with("#1a2b3c")
      expect(google_event.event_label_id).to eq("11111111-2222-3333-4444-555555555555")
      expect(google_event.color_id).to be_nil
      expect(described_class.request_options(google_event)).to eq(event_label_version: 1)
    end

    it "removes the label from an event with no color" do
      google_event = described_class.build(event_data.merge(color_id: nil), labels)

      expect(google_event.event_label_id).to eq("")
      expect(described_class.request_options(google_event)).to eq(event_label_version: 1)
    end

    it "sends the nearest legacy color id when the calendar cannot take labels" do
      allow(labels).to receive_messages(available?: false, label_id_for: nil)

      google_event = described_class.build(event_data.merge(color_id: "#ff0000"), labels)

      expect(google_event.event_label_id).to be_nil
      expect(google_event.color_id).to eq("11")
      expect(described_class.request_options(google_event)).to eq({})
    end

    it "sends the nearest legacy color id when the calendar has no room for another label" do
      allow(labels).to receive(:label_id_for).and_return(nil)

      google_event = described_class.build(event_data.merge(color_id: "#0b8043"), labels)

      expect(google_event.event_label_id).to be_nil
      expect(google_event.color_id).to eq("10")
    end

    it "sends the nearest legacy color id when no labels are given" do
      google_event = described_class.build(event_data.merge(color_id: "#ff0000"))

      expect(google_event.color_id).to eq("11")
      expect(described_class.request_options(google_event)).to eq({})
    end
  end

  describe ".for_friend_meeting" do
    let(:user)   { create(:user) }
    let(:friend) { create(:user, first_name: "Sample", last_name: "Friend", email: "sample.friend@wit.edu") }
    let(:meeting) do
      create(:friend_meeting, :invite_friends, user: user, title: "Synthetic Study Group",
                                               start_time: zone.local(2026, 9, 15, 15), end_time: zone.local(2026, 9, 15, 16))
    end

    before { create(:friend_meeting_attendee, friend_meeting: meeting, user: friend) }

    it "lists the invited friends as attendees" do
      google_event = described_class.for_friend_meeting(meeting, attendees: true)

      expect(google_event.summary).to eq("Synthetic Study Group")
      expect(google_event.attendees.map { |a| [ a.email, a.display_name ] }).to eq([ [ "sample.friend@wit.edu", "Sample Friend" ] ])
    end

    it "lists no attendees when asked not to" do
      expect(described_class.for_friend_meeting(meeting, attendees: false).attendees).to be_nil
    end
  end
end
