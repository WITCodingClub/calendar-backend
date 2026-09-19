# frozen_string_literal: true

require "rails_helper"

RSpec.describe PreferenceResolver do
  let(:user) { create(:user) }
  let(:meeting_time) { create(:course_meeting_time) }

  def university_event(all_day: true, category: "holiday")
    create(:university_calendar_event, category: category, all_day: all_day)
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
      expect(resolved[:color_id]).to eq("#616161")
    end
  end

  describe "the university wide preference" do
    it "turns off reminders for university events and leaves classes alone" do
      create(:calendar_preference, :uni_cal_global, user: user, reminder_settings: [])
      resolver = described_class.new(user)

      expect(resolver.resolve_for(university_event)[:reminder_settings]).to eq([])
      expect(resolver.resolve_for(meeting_time)[:reminder_settings]).to eq(
        [ { "time" => "30", "type" => "minutes", "method" => "popup" } ]
      )
    end

    it "reports itself as the source of the value" do
      create(:calendar_preference, :uni_cal_global, user: user,
             reminder_settings: [ { "time" => "2", "type" => "days", "method" => "popup" } ])

      result = described_class.new(user).resolve_with_sources(university_event)

      expect(result[:sources][:reminder_settings]).to eq("uni_cal_global")
      expect(result[:preferences][:reminder_settings]).to eq(
        [ { "time" => "2", "type" => "days", "method" => "popup" } ]
      )
    end

    it "gives way to a preference for one category" do
      create(:calendar_preference, :uni_cal_global, user: user, reminder_settings: [])
      create(:calendar_preference, :uni_cal_category, user: user,
             reminder_settings: [ { "time" => "1", "type" => "hours", "method" => "popup" } ])

      resolver = described_class.new(user)

      expect(resolver.resolve_for(university_event(category: "holiday"))[:reminder_settings]).to eq(
        [ { "time" => "1", "type" => "hours", "method" => "popup" } ]
      )
      expect(resolver.resolve_for(university_event(category: "deadline"))[:reminder_settings]).to eq([])
    end

    it "gives way to a preference for one event" do
      create(:calendar_preference, :uni_cal_global, user: user, reminder_settings: [])
      event = university_event
      create(:event_preference, user: user, preferenceable: event,
             reminder_settings: [ { "time" => "45", "type" => "minutes", "method" => "popup" } ])

      resolved = described_class.new(user).resolve_for(event)

      expect(resolved[:reminder_settings]).to eq(
        [ { "time" => "45", "type" => "minutes", "method" => "popup" } ]
      )
    end
  end

  describe "the global preference" do
    it "does not reach university events, so class settings stay separate" do
      create(:calendar_preference, user: user,
             reminder_settings: [ { "time" => "5", "type" => "minutes", "method" => "popup" } ])

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
