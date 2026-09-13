# frozen_string_literal: true

require "rails_helper"

RSpec.describe PreferenceResolver do
  let(:user) { User.create!(email: "resolver@wit.edu", password: "password123") }
  let(:term) { Term.create!(uid: 202710, season: :fall, year: 2026) }
  let(:course) do
    Course.create!(
      crn: 54321, term: term, title: "Data Structures", subject: "COMP",
      course_number: 2000, section_number: "01", schedule_type: "lecture",
      start_date: Date.new(2026, 9, 8), end_date: Date.new(2026, 12, 15)
    )
  end
  let(:meeting_time) do
    Course::MeetingTime.create!(
      course: course,
      start_date: Time.zone.local(2026, 9, 8),
      end_date: Time.zone.local(2026, 12, 15, 23, 59, 59),
      begin_time: 1300, end_time: 1445,
      day_of_week: :monday,
      meeting_schedule_type: :lecture, meeting_type: :class_meeting
    )
  end

  def university_event(all_day: true, category: "holiday")
    UniversityCalendarEvent.create!(
      ics_uid: "uce-#{SecureRandom.hex(4)}",
      summary: "Fall Break",
      category: category,
      all_day: all_day,
      start_time: Time.zone.local(2026, 10, 12),
      end_time: Time.zone.local(2026, 10, 12, 23, 59, 59)
    )
  end

  before { allow(GoogleCalendarSyncJob).to receive(:perform_later) }

  describe "system defaults for university events" do
    it "reminds 15 hours before an all day event, which is 9AM the day before" do
      resolved = described_class.new(user).resolve_for(university_event(all_day: true))

      expect(resolved[:reminder_settings]).to eq(
        [ { "time" => "15", "type" => "hours", "method" => "popup" } ]
      )
    end

    it "reminds 30 minutes before an event that has a start time" do
      resolved = described_class.new(user).resolve_for(university_event(all_day: false))

      expect(resolved[:reminder_settings]).to eq(
        [ { "time" => "30", "type" => "minutes", "method" => "popup" } ]
      )
    end

    it "uses the university templates even when the event has no category" do
      resolved = described_class.new(user).resolve_for(university_event(category: nil))

      expect(resolved[:title_template]).to eq("{{summary}}")
      expect(resolved[:color_id]).to eq(8)
    end
  end

  describe "the university wide preference" do
    it "turns off reminders for university events and leaves classes alone" do
      user.calendar_preferences.create!(scope: :uni_cal_global, reminder_settings: [])
      resolver = described_class.new(user)

      expect(resolver.resolve_for(university_event)[:reminder_settings]).to eq([])
      expect(resolver.resolve_for(meeting_time)[:reminder_settings]).to eq(
        [ { "time" => "30", "type" => "minutes", "method" => "popup" } ]
      )
    end

    it "reports itself as the source of the value" do
      user.calendar_preferences.create!(
        scope: :uni_cal_global,
        reminder_settings: [ { "time" => "2", "type" => "days", "method" => "popup" } ]
      )

      result = described_class.new(user).resolve_with_sources(university_event)

      expect(result[:sources][:reminder_settings]).to eq("uni_cal_global")
      expect(result[:preferences][:reminder_settings]).to eq(
        [ { "time" => "2", "type" => "days", "method" => "popup" } ]
      )
    end

    it "gives way to a preference for one category" do
      user.calendar_preferences.create!(scope: :uni_cal_global, reminder_settings: [])
      user.calendar_preferences.create!(
        scope: :uni_cal_category, event_type: "holiday",
        reminder_settings: [ { "time" => "1", "type" => "hours", "method" => "popup" } ]
      )

      resolver = described_class.new(user)

      expect(resolver.resolve_for(university_event(category: "holiday"))[:reminder_settings]).to eq(
        [ { "time" => "1", "type" => "hours", "method" => "popup" } ]
      )
      expect(resolver.resolve_for(university_event(category: "deadline"))[:reminder_settings]).to eq([])
    end

    it "gives way to a preference for one event" do
      user.calendar_preferences.create!(scope: :uni_cal_global, reminder_settings: [])
      event = university_event
      user.event_preferences.create!(
        preferenceable: event,
        reminder_settings: [ { "time" => "45", "type" => "minutes", "method" => "popup" } ]
      )

      resolved = described_class.new(user).resolve_for(event)

      expect(resolved[:reminder_settings]).to eq(
        [ { "time" => "45", "type" => "minutes", "method" => "popup" } ]
      )
    end
  end

  describe "the global preference" do
    it "does not reach university events, so class settings stay separate" do
      user.calendar_preferences.create!(
        scope: :global,
        reminder_settings: [ { "time" => "5", "type" => "minutes", "method" => "popup" } ]
      )

      resolver = described_class.new(user)

      expect(resolver.resolve_for(meeting_time)[:reminder_settings]).to eq(
        [ { "time" => "5", "type" => "minutes", "method" => "popup" } ]
      )
      expect(resolver.resolve_for(university_event)[:reminder_settings]).to eq(
        [ { "time" => "15", "type" => "hours", "method" => "popup" } ]
      )
    end
  end

  describe "the do not disturb switch" do
    it "clears the reminders of university events as well" do
      user.disable_notifications!

      expect(described_class.new(user).resolve_for(university_event)[:reminder_settings]).to eq([])
    end
  end
end
