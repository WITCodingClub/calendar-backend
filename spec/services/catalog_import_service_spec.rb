# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogImportService do
  let!(:term) do
    Term.create!(
      uid: 202710,
      season: :fall,
      year: 2026,
      start_date: Date.new(2026, 9, 8),
      end_date: Date.new(2026, 12, 15)
    )
  end

  def catalog_row(crn:, sequence:, schedule_type: "Lecture (LEC)", link_identifier: nil, is_section_linked: nil)
    {
      "courseReferenceNumber"   => crn.to_s,
      "term"                    => "202710",
      "courseTitle"             => "General Chemistry",
      "subject"                 => "CHEM",
      "courseNumber"            => "1000",
      "sequenceNumber"          => sequence,
      "scheduleTypeDescription" => schedule_type,
      "creditHours"             => 4,
      "linkIdentifier"          => link_identifier,
      "isSectionLinked"         => is_section_linked,
      "meetingsFaculty"         => [],
      "faculty"                 => []
    }
  end

  describe "link identifiers" do
    it "stores the identifier on a new course" do
      described_class.new([ catalog_row(crn: 16861, sequence: "1A", link_identifier: "A1", is_section_linked: true) ]).call!

      course = Course.find_by(crn: 16861, term: term)
      expect(course.link_identifier).to eq("A1")
      expect(course.is_section_linked).to be(true)
    end

    it "leaves the identifier empty when Banner sends none" do
      described_class.new([ catalog_row(crn: 16862, sequence: "01") ]).call!

      course = Course.find_by(crn: 16862, term: term)
      expect(course.link_identifier).to be_nil
      expect(course.is_section_linked).to be(false)
    end

    it "adds the identifier to a course that was imported without one" do
      described_class.new([ catalog_row(crn: 16863, sequence: "1A") ]).call!
      described_class.new([ catalog_row(crn: 16863, sequence: "1A", link_identifier: "A1", is_section_linked: true) ]).call!

      course = Course.find_by(crn: 16863, term: term)
      expect(course.link_identifier).to eq("A1")
      expect(course.is_section_linked).to be(true)
    end

    it "clears the identifier when Banner drops the pairing" do
      described_class.new([ catalog_row(crn: 16864, sequence: "1A", link_identifier: "A1", is_section_linked: true) ]).call!
      described_class.new([ catalog_row(crn: 16864, sequence: "1A") ]).call!

      course = Course.find_by(crn: 16864, term: term)
      expect(course.link_identifier).to be_nil
      expect(course.is_section_linked).to be(false)
    end

    it "reads a string flag from Banner as a boolean" do
      described_class.new([ catalog_row(crn: 16865, sequence: "2A", schedule_type: "Laboratory (LAB)",
                                        link_identifier: "B1", is_section_linked: "true") ]).call!

      expect(Course.find_by(crn: 16865, term: term).is_section_linked).to be(true)
    end
  end
end
