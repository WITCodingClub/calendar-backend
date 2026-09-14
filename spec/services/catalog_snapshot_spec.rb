# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogSnapshot do
  # Through JSON, as in the real file.
  def export(**options) = JSON.parse(JSON.generate(described_class.export(**options)))

  def table_counts = described_class::TABLES.to_h { |table, (model, _columns)| [ table, model.constantize.count ] }

  def clear_catalog
    described_class::TABLES.values.reverse_each { |model, _columns| model.constantize.delete_all }
  end

  let(:term) { create(:term, uid: 202710, year: 2026, season: :fall) }
  let(:course) { create(:course, term: term) }

  describe ".export" do
    it "exports faculty names and titles, with a placeholder email" do
      faculty = create(:faculty, first_name: "Ada", last_name: "Byron", title: "Professor", phone: "617-555-0100",
                                 office_location: "ANNX 306", photo_url: "https://example.com/ada.jpg",
                                 rmp_id: "rmp-ada", directory_raw_data: { "raw_html" => "<p>Ada</p>" })
      course.faculties << faculty

      row = export["tables"]["faculties"].sole

      expect(row.keys).to match_array(described_class::TABLES["faculties"].last + [ "email" ])
      expect(row).to include("first_name" => "Ada", "last_name" => "Byron", "title" => "Professor",
                             "email" => "faculty-#{faculty.id}@example.com")
    end

    it "leaves out faculty who teach no exported course" do
      course
      create(:faculty)

      expect(export["tables"]["faculties"]).to be_empty
    end

    it "keeps personal columns and user tables out of every table" do
      personal = %w[email phone office_location photo_url directory_raw_data rmp_raw_data rmp_id]

      described_class::TABLES.each_value do |model, columns|
        expect(columns & personal).to be_empty
        expect(model.constantize.column_names).not_to include("user_id")
      end
    end

    it "exports the most recent terms that have courses" do
      create(:course, term: create(:term, uid: 202610, year: 2025, season: :fall))
      course
      create(:term, uid: 202810, year: 2027, season: :fall)

      expect(export(term_count: 1)["tables"]["terms"].map { |row| row["uid"] }).to eq([ 202710 ])
    end
  end

  describe ".import" do
    it "restores an export into empty catalog tables" do
      room = create(:room, building: create(:building, abbreviation: "ANNX", name: "Test Annex"), number: "306")
      faculty = create(:faculty)
      course.faculties << faculty
      meeting_time = create(:course_meeting_time, course: course)
      meeting_time.rooms << room
      create(:final_exam, term: term, course: course, crn: course.crn, combined_crns: %w[10001 10002])
      create(:university_calendar_event, term: term, recurrence: [ "RRULE:FREQ=WEEKLY" ])

      data = export
      counts = table_counts
      course_attributes = course.reload.attributes.except("created_at", "updated_at")
      clear_catalog

      described_class.import(data)

      expect(table_counts).to eq(counts)
      expect(Course.find(course.id).attributes.except("created_at", "updated_at")).to eq(course_attributes)
      expect(FinalExam.sole.combined_crns).to eq(%w[10001 10002])
      expect(UniversityCalendarEvent.sole.recurrence).to eq([ "RRULE:FREQ=WEEKLY" ])
      expect(Course::MeetingTime.find(meeting_time.id).rooms).to eq([ Room.find(room.id) ])
      expect(Faculty.find(faculty.id).email).to eq("faculty-#{faculty.id}@example.com")
    end

    it "moves the id sequences past the imported rows" do
      course
      data = export
      clear_catalog
      described_class.import(data)

      expect(create(:course, term: Term.sole).id).to be > course.id
    end

    it "refuses catalog tables that already have rows" do
      course
      data = export

      expect { described_class.import(data) }.to raise_error(described_class::CatalogNotEmpty, /courses/)
    end

    it "refuses an unknown format version" do
      expect { described_class.import("format_version" => 99, "tables" => {}) }.to raise_error(ArgumentError, /format/)
    end
  end

  describe ".write and .read" do
    it "round-trips data through a gzipped file" do
      data = { "format_version" => 1, "tables" => { "terms" => [ { "uid" => 202710 } ] } }

      Dir.mktmpdir do |dir|
        path = File.join(dir, "catalog.json.gz")
        described_class.write(path, data)

        expect(described_class.read(path)).to eq(data)
      end
    end
  end
end
