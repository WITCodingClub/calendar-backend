# frozen_string_literal: true

require "rails_helper"

RSpec.describe MeetingTimeProcessor do
  describe ".process_meeting_time" do
    let(:term) { create(:term) }
    let(:course) { create(:course, term: term, title: "Data Structures", course_number: 201, subject: "CS", crn: 99901) }
    let(:building) { create(:building, name: "Beatty Hall", abbreviation: "BE") }
    let(:room) { create(:room, building: building, number: "101") }
    let(:meeting_time) do
      create(:meeting_time, course: course, room: room,
             begin_time: 900, end_time: 1050, day_of_week: :monday,
             meeting_schedule_type: :lecture)
    end

    subject(:result) { described_class.process_meeting_time(meeting_time) }

    it "returns a hash with a top-level :id key" do
      expect(result[:id]).to eq(meeting_time.id)
    end

    it "includes formatted begin and end times" do
      expect(result[:begin_time]).to eq(meeting_time.fmt_begin_time)
      expect(result[:end_time]).to eq(meeting_time.fmt_end_time)
    end

    it "includes start and end dates" do
      expect(result[:start_date]).to eq(meeting_time.start_date)
      expect(result[:end_date]).to eq(meeting_time.end_date)
    end

    it "includes the day of week" do
      expect(result[:day_of_week]).to eq(meeting_time.day_of_week)
    end

    it "includes the meeting schedule type" do
      expect(result[:meeting_schedule_type]).to eq(meeting_time.meeting_schedule_type)
    end

    it "includes building name and abbreviation" do
      expect(result.dig(:location, :building, :name)).to eq("Beatty Hall")
      expect(result.dig(:location, :building, :abbreviation)).to eq("BE")
    end

    it "includes the formatted room number" do
      expect(result.dig(:location, :room)).to eq(room.formatted_number)
    end

    it "includes course title, number, prefix, and crn" do
      expect(result.dig(:course, :title)).to eq("Data Structures")
      expect(result.dig(:course, :course_number)).to eq(201)
      expect(result.dig(:course, :prefix)).to eq("CS")
      expect(result.dig(:course, :crn)).to eq(99901)
    end

    context "when the meeting_time has no building (edge case)" do
      it "sets the building location to nil gracefully" do
        meeting_time_stub = instance_double(
          MeetingTime,
          id: 999,
          fmt_begin_time: "9:00 AM",
          fmt_end_time: "10:50 AM",
          start_date: 1.week.from_now,
          end_date: 3.months.from_now,
          day_of_week: :tuesday,
          meeting_schedule_type: :lecture,
          building: nil,
          room: nil,
          course: course
        )

        result = described_class.process_meeting_time(meeting_time_stub)
        expect(result.dig(:location, :building)).to be_nil
        expect(result.dig(:location, :room)).to be_nil
      end
    end
  end
end
