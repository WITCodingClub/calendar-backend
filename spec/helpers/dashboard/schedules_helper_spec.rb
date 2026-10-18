# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::SchedulesHelper, type: :helper do
  let(:term) { build(:term, start_date: Date.new(2026, 9, 8), end_date: Date.new(2026, 12, 15)) }

  def entry(day, color: "#d50000", **meeting_time)
    {
      course:       { subject: "COMP", course_number: 1050, title: "Computer Science I" },
      meeting_time: {
        day:                day,
        begin_time:         "09:00",
        end_time:           "10:15",
        begin_time_display: "9:00 AM",
        end_time_display:   "10:15 AM",
        building_room:      "Wentworth 210",
        calendar_config:    { color_id: color }
      }.merge(meeting_time)
    }
  end

  def schedule_with(*entries)
    ScheduleLoading::Schedule.new(
      terms:           [],
      selected_term:   term,
      view_mode:       "week",
      today:           Date.new(2026, 9, 14),
      week_start:      Date.new(2026, 9, 14),
      month_date:      Date.new(2026, 9, 1),
      courses:         [],
      schedule_by_day: entries.group_by { |e| e[:meeting_time][:day].to_s },
      no_class_dates:  []
    )
  end

  describe "#schedule_week_days" do
    it "shows Monday to Friday when no course meets on a weekend" do
      days = helper.schedule_week_days(schedule_with(entry(:monday)))

      expect(days).to eq((Date.new(2026, 9, 14)..Date.new(2026, 9, 18)).to_a)
    end

    it "adds Saturday and Sunday when a course meets on them" do
      days = helper.schedule_week_days(schedule_with(entry(:saturday), entry(:sunday)))

      expect(days.last(2)).to eq([ Date.new(2026, 9, 19), Date.new(2026, 9, 20) ])
    end

    it "adds only the weekend day that has a course" do
      days = helper.schedule_week_days(schedule_with(entry(:sunday)))

      expect(days.map(&:wday)).to eq([ 1, 2, 3, 4, 5, 0 ])
    end
  end

  describe "#schedule_sessions_on" do
    it "returns the meetings on the day in start time order" do
      late  = entry(:monday, begin_time: "13:00")
      early = entry(:monday, begin_time: "08:00")

      expect(helper.schedule_sessions_on(schedule_with(late, early), Date.new(2026, 9, 14))).to eq([ early, late ])
    end

    it "skips a meeting outside its own dates" do
      later = entry(:monday, start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 12, 1))

      expect(helper.schedule_sessions_on(schedule_with(later), Date.new(2026, 9, 14))).to be_empty
    end
  end

  describe "#schedule_entry_label" do
    it "joins the course, title, time and room" do
      expect(helper.schedule_entry_label(entry(:monday)))
        .to eq("COMP 1050, Computer Science I, 9:00 AM – 10:15 AM, Wentworth 210")
    end

    it "leaves out a missing time and room" do
      label = helper.schedule_entry_label(entry(:monday, begin_time_display: nil, building_room: nil))

      expect(label).to eq("COMP 1050, Computer Science I")
    end
  end

  describe "#schedule_entry_style" do
    it "tints the background and borders the block with the course color" do
      expect(helper.schedule_entry_style(entry(:monday)))
        .to eq("background-color: #d5000026; border-left: 3px solid #d50000")
    end

    it "uses the default color for a value that is not a hex color" do
      style = helper.schedule_entry_style(entry(:monday, color: "red; position: fixed"), border_width: 2)

      expect(style).to eq("background-color: #3f51b526; border-left: 2px solid #3f51b5")
    end
  end
end
