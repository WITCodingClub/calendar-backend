# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::MeetingTimesIngest do
  let(:course) { create(:course) }

  let(:raw_meeting_times) do
    [
      {
        "startDate"           => "09/08/2026",
        "endDate"             => "12/15/2026",
        "beginTime"           => "1300",
        "endTime"             => "1445",
        "building"            => "IRAH",
        "buildingDescription" => "Ira Allen Hall",
        "room"                => "112",
        "monday"              => true,
        "wednesday"           => true
      }
    ]
  end

  it "creates one meeting time per active day and returns their ids" do
    touched_ids = described_class.call(course: course, raw_meeting_times: raw_meeting_times)

    expect(course.meeting_times.count).to eq(2)
    expect(touched_ids).to match_array(course.meeting_times.pluck(:id))
  end

  it "reuses existing meeting times on re-ingest instead of creating new rows" do
    first_ids = described_class.call(course: course, raw_meeting_times: raw_meeting_times)
    second_ids = described_class.call(course: course, raw_meeting_times: raw_meeting_times)

    expect(second_ids).to match_array(first_ids)
    expect(course.meeting_times.count).to eq(2)
  end

  it "does not include stale meeting times in the returned ids" do
    stale = create(:course_meeting_time, course: course, day_of_week: :friday)

    touched_ids = described_class.call(course: course, raw_meeting_times: raw_meeting_times)

    expect(touched_ids).not_to include(stale.id)
  end

  it "swaps the linked room when Banner reports a new one" do
    described_class.call(course: course, raw_meeting_times: raw_meeting_times)

    moved = raw_meeting_times.map { |mt| mt.merge("room" => "308") }
    described_class.call(course: course, raw_meeting_times: moved)

    expect(course.meeting_times.count).to eq(2)
    expect(course.meeting_times.flat_map { |mt| mt.rooms.map(&:number) }.uniq).to eq([ "308" ])
  end

  it "drops the room when Banner stops reporting one" do
    described_class.call(course: course, raw_meeting_times: raw_meeting_times)

    unassigned = raw_meeting_times.map { |mt| mt.merge("room" => nil) }
    described_class.call(course: course, raw_meeting_times: unassigned)

    expect(course.meeting_times.flat_map { |mt| mt.rooms.map(&:number) }.uniq).to eq([ "0" ])
  end

  describe "meeting schedule type" do
    it "takes the type Banner sends with the meeting" do
      described_class.call(course: course, raw_meeting_times: [ raw_meeting_times.first.merge("meetingScheduleType" => "LAB") ])

      expect(course.meeting_times.pluck(:meeting_schedule_type).uniq).to eq([ "laboratory" ])
    end

    it "uses the section's schedule type when the meeting has none, as the nightly sync sends" do
      lab = create(:course, schedule_type: :laboratory)

      described_class.call(course: lab, raw_meeting_times: described_class.normalize_leopard_web([ {
        "startDate" => "01/12/2027", "endDate" => "04/20/2027", "startTime" => "1715", "endTime" => "1900",
        "building" => "IRAH", "room" => "206", "days" => { "wednesday" => true }
      } ]))

      expect(lab.meeting_times.pluck(:meeting_schedule_type)).to eq([ "laboratory" ])
    end

    it "treats online and rotating labs as labs" do
      online_lab = create(:course, schedule_type: :online_sync_lab)

      described_class.call(course: online_lab, raw_meeting_times: raw_meeting_times)

      expect(online_lab.meeting_times.pluck(:meeting_schedule_type).uniq).to eq([ "laboratory" ])
    end

    it "keeps a lecture section's meetings as lectures" do
      described_class.call(course: course, raw_meeting_times: raw_meeting_times)

      expect(course.meeting_times.pluck(:meeting_schedule_type).uniq).to eq([ "lecture" ])
    end
  end

  describe ".normalize_leopard_web" do
    let(:leopard_web_payload) do
      [
        {
          "building"             => "IRAH",
          "building_description" => "Ira Allen Hall",
          "room"                 => "112",
          "startDate"            => "09/08/2026",
          "endDate"              => "12/15/2026",
          "startTime"            => "1300",
          "endTime"              => "1445",
          "days"                 => { "monday" => true, "wednesday" => true }
        }
      ]
    end

    it "reshapes the Banner payload into the keys the ingest reads" do
      expect(described_class.normalize_leopard_web(leopard_web_payload)).to eq(
        [
          {
            "startDate"           => "09/08/2026",
            "endDate"             => "12/15/2026",
            "beginTime"           => "1300",
            "endTime"             => "1445",
            "building"            => "IRAH",
            "buildingDescription" => "Ira Allen Hall",
            "room"                => "112",
            "monday"              => true,
            "tuesday"             => nil,
            "wednesday"           => true,
            "thursday"            => nil,
            "friday"              => nil,
            "saturday"            => nil,
            "sunday"              => nil
          }
        ]
      )
    end

    it "returns an empty array for a nil payload" do
      expect(described_class.normalize_leopard_web(nil)).to eq([])
    end
  end
end
