# frozen_string_literal: true

require "rails_helper"

RSpec.describe MeetingTimesIngestService do
  let(:term) { create(:term) }
  let(:course) { create(:course, term: term) }

  describe "#call" do
    let(:building) { create(:building, abbreviation: "BEATT", name: "Beatty Hall") }

    context "with alphanumeric room numbers" do
      it "preserves the full room number including letters" do
        raw_meeting_times = [
          {
            "startDate" => "01/06/2026",
            "endDate" => "04/14/2026",
            "beginTime" => "1000",
            "endTime" => "1145",
            "wednesday" => true,
            "building" => "BEATT",
            "buildingDescription" => "Beatty Hall",
            "room" => "M204"
          }
        ]

        described_class.call(course: course, raw_meeting_times: raw_meeting_times)

        meeting_time = course.meeting_times.first
        expect(meeting_time.room.number).to eq("M204")
      end

      it "handles room numbers with trailing letters" do
        raw_meeting_times = [
          {
            "startDate" => "01/06/2026",
            "endDate" => "04/14/2026",
            "beginTime" => "1000",
            "endTime" => "1145",
            "monday" => true,
            "building" => "TEST",
            "buildingDescription" => "Test Building",
            "room" => "101A"
          }
        ]

        described_class.call(course: course, raw_meeting_times: raw_meeting_times)

        meeting_time = course.meeting_times.first
        expect(meeting_time.room.number).to eq("101A")
      end

      it "defaults to '0' for blank room numbers" do
        raw_meeting_times = [
          {
            "startDate" => "01/06/2026",
            "endDate" => "04/14/2026",
            "beginTime" => "1000",
            "endTime" => "1145",
            "monday" => true,
            "building" => "TBD",
            "buildingDescription" => "To Be Determined",
            "room" => ""
          }
        ]

        described_class.call(course: course, raw_meeting_times: raw_meeting_times)

        meeting_time = course.meeting_times.first
        expect(meeting_time.room.number).to eq("0")
      end
    end

    context "when updating existing meeting times" do
      it "updates the room when it changes" do
        # Create initial meeting time with TBD room
        tbd_building = create(:building, abbreviation: "TBD", name: "To Be Determined")
        tbd_room = create(:room, building: tbd_building, number: "0")

        meeting_time = create(
          :meeting_time,
          course: course,
          room: tbd_room,
          start_date: Time.zone.local(2026, 1, 6, 0, 0, 0),
          end_date: Time.zone.local(2026, 4, 14, 23, 59, 59),
          begin_time: 1000,
          end_time: 1145,
          day_of_week: :wednesday
        )

        # Now import with updated room data
        raw_meeting_times = [
          {
            "startDate" => "01/06/2026",
            "endDate" => "04/14/2026",
            "beginTime" => "1000",
            "endTime" => "1145",
            "wednesday" => true,
            "building" => "BEATT",
            "buildingDescription" => "Beatty Hall",
            "room" => "M204"
          }
        ]

        expect {
          described_class.call(course: course, raw_meeting_times: raw_meeting_times)
        }.not_to change { MeetingTime.count }

        meeting_time.reload
        expect(meeting_time.room.number).to eq("M204")
        expect(meeting_time.room.building.abbreviation).to eq("BEATT")
      end

      it "does not create duplicate meeting times when room changes" do
        tbd_building = create(:building, abbreviation: "TBD", name: "To Be Determined")
        tbd_room = create(:room, building: tbd_building, number: "0")

        create(
          :meeting_time,
          course: course,
          room: tbd_room,
          start_date: Time.zone.local(2026, 1, 6, 0, 0, 0),
          end_date: Time.zone.local(2026, 4, 14, 23, 59, 59),
          begin_time: 1000,
          end_time: 1145,
          day_of_week: :wednesday
        )

        raw_meeting_times = [
          {
            "startDate" => "01/06/2026",
            "endDate" => "04/14/2026",
            "beginTime" => "1000",
            "endTime" => "1145",
            "wednesday" => true,
            "building" => "BEATT",
            "buildingDescription" => "Beatty Hall",
            "room" => "M204"
          }
        ]

        expect {
          described_class.call(course: course, raw_meeting_times: raw_meeting_times)
        }.not_to change { course.meeting_times.count }
      end
    end
  end
end
