# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogImportService do
  let!(:term) { Term.create!(uid: 202710, season: :fall, year: 2026) }

  # One entry of the searchResults payload, cut down to the keys the service
  # reads. Seat counts come from this same payload, so importing them needs no
  # extra request to LeopardWeb.
  def catalog_course(overrides = {})
    {
      "courseReferenceNumber"   => "12345",
      "term"                    => "202710",
      "subject"                 => "COMP",
      "courseNumber"            => "2000",
      "sequenceNumber"          => "01",
      "courseTitle"             => "Data Structures",
      "creditHours"             => 4,
      "scheduleTypeDescription" => "Lecture (LEC)",
      "maximumEnrollment"       => 30,
      "enrollment"              => 28,
      "seatsAvailable"          => 2,
      "meetingsFaculty"         => [
        {
          "meetingTime" => {
            "startDate"           => "09/08/2026",
            "endDate"             => "12/15/2026",
            "beginTime"           => "1300",
            "endTime"             => "1445",
            "building"            => "IRAH",
            "buildingDescription" => "Ira Allen Hall",
            "room"                => "112",
            "monday"              => true
          }
        }
      ],
      "faculty"                 => []
    }.merge(overrides)
  end

  def imported_course
    Course.find_by!(crn: 12345, term: term)
  end

  describe "seat counts" do
    it "stores seat counts from the catalog payload on a new course" do
      described_class.call([ catalog_course ])

      expect(imported_course).to have_attributes(seats_capacity: 30, seats_available: 2)
    end

    it "refreshes seat counts on a course that already exists" do
      described_class.call([ catalog_course ])
      described_class.call([ catalog_course("seatsAvailable" => 0, "enrollment" => 30) ])

      expect(imported_course).to have_attributes(seats_capacity: 30, seats_available: 0)
    end

    it "keeps a negative seat count so an over-enrolled section is not read as full" do
      # Banner reports maximumEnrollment - enrollment, which goes negative when
      # more students are registered than the cap allows.
      described_class.call([ catalog_course("maximumEnrollment" => 0, "seatsAvailable" => -11) ])

      expect(imported_course).to have_attributes(seats_capacity: 0, seats_available: -11)
    end

    it "leaves seat counts blank when the payload omits them" do
      described_class.call([ catalog_course("maximumEnrollment" => nil, "seatsAvailable" => nil) ])

      expect(imported_course).to have_attributes(seats_capacity: nil, seats_available: nil)
    end

    it "does not overwrite known seat counts with a payload that omits them" do
      described_class.call([ catalog_course ])
      described_class.call([ catalog_course("maximumEnrollment" => nil, "seatsAvailable" => nil) ])

      expect(imported_course).to have_attributes(seats_capacity: 30, seats_available: 2)
    end

    it "lowers capacity and seats together so the two stay consistent" do
      described_class.call([ catalog_course ])
      described_class.call([ catalog_course("maximumEnrollment" => 5, "seatsAvailable" => 1) ])

      expect(imported_course).to have_attributes(seats_capacity: 5, seats_available: 1)
    end
  end
end
