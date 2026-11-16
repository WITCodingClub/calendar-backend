# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::BannerSection do
  describe ".from_search" do
    let(:data) do
      {
        "courseReferenceNumber" => "16004", "term" => "202710",
        "scheduleTypeDescription" => "Lecture (LEC)",
        "maximumEnrollment" => 30, "seatsAvailable" => -2,
        "waitCapacity" => 5, "waitAvailable" => nil,
        "crossList" => "03", "crossListCapacity" => 40, "crossListAvailable" => 12,
        "creditHours" => nil, "creditHourLow" => 4,
        "meetingsFaculty" => [
          { "meetingTime" => { "startDate" => "09/08/2026", "endDate" => "12/15/2026", "beginTime" => "0800",
                               "endTime" => "0950", "building" => "TBD", "room" => "", "monday" => true } },
          { "meetingTime" => { "startDate" => "09/08/2026", "endDate" => "12/15/2026", "beginTime" => "0800",
                               "endTime" => "0950", "building" => "WENTW", "buildingDescription" => "Wentworth Hall",
                               "room" => "212", "monday" => true } }
        ]
      }
    end

    let(:section) { described_class.from_search(data) }

    it "keeps each count pair only when Banner sends both numbers, and keeps a negative count" do
      expect(section.counts).to eq(seats_capacity: 30, seats_available: -2,
                                   cross_list_capacity: 40, cross_list_available: 12)
    end

    it "clears the cross-list counts of a section that left its group" do
      expect(described_class.from_search(data.except("crossList")).counts)
        .to include(cross_list_capacity: nil, cross_list_available: nil)
    end

    it "reads the schedule type key from Banner's text" do
      expect(section.schedule_type).to eq("lecture")
    end

    it "takes creditHourLow when an older term sends creditHours as null" do
      expect(section.attributes[:credit_hours]).to eq(4)
    end

    it "keeps one copy of a meeting Banner lists twice, the one with a real room" do
      expect(section.meeting_times.map { |m| [ m.building, m.room ] }).to eq([ [ "WENTW", "212" ] ])
    end
  end

  describe ".from_class_details" do
    it "reads getClassDetails seats and meetings" do
      section = described_class.from_class_details(
        title: " Data Structures ", schedule_type: "No Section specified schedule type",
        seats_capacity: 30, seats_available: 5, waitlist_capacity: nil, waitlist_available: 1,
        meeting_times: [ { "startDate" => "09/08/2026", "endDate" => "12/15/2026", "startTime" => "1300",
                           "endTime" => "1445", "building" => "IRAH", "building_description" => "Ira Allen Hall",
                           "room" => "112", "days" => { "monday" => true, "wednesday" => true } } ]
      )

      expect(section.attributes).to eq(title: "Data Structures")
      expect(section.schedule_type).to be_nil
      expect(section.counts).to eq(seats_capacity: 30, seats_available: 5)
      expect(section.meeting_times.first).to have_attributes(
        start_date: Date.new(2026, 9, 8), begin_time: 1300, end_time: 1445,
        days: %w[monday wednesday], building: "IRAH", building_name: "Ira Allen Hall", room: "112"
      )
    end
  end

  describe Catalog::BannerSection::Meeting do
    it "reads Banner's and the extension's time forms" do
      expect([ "800", "0800", "13:15", "1:15 PM", "12:05 AM", "2460", "soon" ].map { |t| described_class.parse_time(t) })
        .to eq([ 800, 800, 1315, 1315, 5, nil, nil ])
    end

    it "reads ISO and US dates" do
      expect([ "2026-09-08", "09/08/2026", "", "13/45/2026" ].map { |d| described_class.parse_date(d) })
        .to eq([ Date.new(2026, 9, 8), Date.new(2026, 9, 8), nil, nil ])
    end

    it "treats a TBD building, room 0, and a blank room as no real place" do
      place = ->(building, room) { described_class.from_search("building" => building, "room" => room).tbd_location? }

      expect([ place.call("TBD", "112"), place.call("WENTW", "0"), place.call("WENTW", ""), place.call("", "112") ])
        .to all(be(true))
      expect(place.call("WENTW", "112/114")).to be(false)
    end
  end
end
