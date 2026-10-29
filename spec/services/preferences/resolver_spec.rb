# frozen_string_literal: true

require "rails_helper"

RSpec.describe Preferences::Resolver do
  let(:user) { create(:user) }
  let(:meeting_time) { create(:course_meeting_time) }

  def university_event(all_day: true, category: "holiday")
    create(:university_calendar_event, category: category, all_day: all_day)
  end

  before { allow(CourseCalendars::SyncJob).to receive(:perform_later) }

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

  describe "the system default title" do
    def default_title_for(course)
      meeting = create(:course_meeting_time, course: course)
      template = described_class.new(user).resolve_for(meeting)[:title_template]
      Preferences::TemplateRenderer.new.render(template, Preferences::TemplateRenderer.build_context_from_meeting_time(meeting))
    end

    it "adds Lab to a lab whose title does not have it" do
      expect(default_title_for(create(:course, schedule_type: :laboratory, title: "Computer Science I")))
        .to eq("Computer Science I - Lab")
    end

    it "does not add Lab twice to a lab whose title has it" do
      expect(default_title_for(create(:course, schedule_type: :laboratory, title: "Computer Science I - Lab")))
        .to eq("Computer Science I - Lab")
    end

    it "leaves a lecture title alone" do
      expect(default_title_for(create(:course, schedule_type: :lecture, title: "Computer Science I")))
        .to eq("Computer Science I")
    end
  end

  describe "the do not disturb switch" do
    it "clears the reminders of university events as well" do
      user.disable_notifications!

      expect(described_class.new(user).resolve_for(university_event)[:reminder_settings]).to eq([])
    end
  end

  describe "#last_changed_at_for" do
    let(:old_time) { 2.days.ago.change(usec: 0) }
    let(:new_time) { 1.hour.ago.change(usec: 0) }

    # Each user gets an extension config, which gives the default colors.
    before { user.user_extension_config.update_column(:updated_at, old_time) }

    it "is the extension config change when no preference applies" do
      expect(described_class.new(user).last_changed_at_for(meeting_time)).to eq(old_time)
    end

    it "is the latest change of the event preference and the calendar preferences on its path" do
      create(:calendar_preference, user: user, color_id: "#a4bdfc", updated_at: old_time)
      create(:event_preference, user: user, preferenceable: meeting_time, color_id: "#7ae7bf", updated_at: new_time)

      expect(described_class.new(user).last_changed_at_for(meeting_time)).to eq(new_time)
    end

    it "ignores the preference of another event" do
      create(:event_preference, user: user, color_id: "#7ae7bf", updated_at: new_time)

      expect(described_class.new(user).last_changed_at_for(meeting_time)).to eq(old_time)
    end

    it "ignores class preferences for a university event" do
      create(:calendar_preference, user: user, color_id: "#a4bdfc", updated_at: new_time)
      user.user_extension_config.update_column(:updated_at, new_time)
      create(:calendar_preference, :uni_cal_global, user: user, color_id: "#7ae7bf", updated_at: old_time)

      expect(described_class.new(user).last_changed_at_for(university_event)).to eq(old_time)
    end
  end
end
