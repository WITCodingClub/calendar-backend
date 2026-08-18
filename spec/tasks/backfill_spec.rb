# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "backfill rake tasks" do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  let!(:term) do
    Term.create!(
      uid: 202710,
      season: :fall,
      year: 2026,
      start_date: Date.new(2026, 9, 8),
      end_date: Date.new(2026, 12, 15)
    )
  end

  def run_task(name, *args)
    task = Rake::Task[name]
    task.reenable
    task.invoke(*args)
  end

  def course(crn:, section_number: "01", schedule_type: "LEC", **attrs)
    Course.create!({
      crn: crn,
      term: term,
      title: "General Chemistry",
      subject: "CHEM",
      course_number: 1000,
      section_number: section_number,
      schedule_type: schedule_type,
      start_date: term.start_date,
      end_date: term.end_date
    }.merge(attrs))
  end

  describe "backfill:seats" do
    before do
      # The task pauses between calls to be gentle on Banner. Tests do not wait.
      allow_any_instance_of(Object).to receive(:sleep)
    end

    it "writes the seat counts Banner reports" do
      target = course(crn: 11111)

      allow(LeopardWebService).to receive(:get_enrollment_info)
        .with(term: "202710", course_reference_number: "11111")
        .and_return({ enrollment: { actual: 18, maximum: 24, seats_available: 6 } })

      run_task("backfill:seats", "202710")

      target.reload
      expect(target.seats_capacity).to eq(24)
      expect(target.seats_available).to eq(6)
    end

    it "skips courses that already have seat counts" do
      course(crn: 22222, seats_capacity: 24, seats_available: 6)

      expect(LeopardWebService).not_to receive(:get_enrollment_info)

      run_task("backfill:seats", "202710")
    end

    it "leaves the row alone when Banner has no answer" do
      target = course(crn: 33333)

      allow(LeopardWebService).to receive(:get_enrollment_info).and_return(nil)

      run_task("backfill:seats", "202710")

      expect(target.reload.seats_capacity).to be_nil
    end

    it "keeps going after one course fails" do
      first  = course(crn: 44444)
      second = course(crn: 55555)

      allow(LeopardWebService).to receive(:get_enrollment_info)
        .with(term: "202710", course_reference_number: "44444")
        .and_raise(StandardError, "Banner is down")
      allow(LeopardWebService).to receive(:get_enrollment_info)
        .with(term: "202710", course_reference_number: "55555")
        .and_return({ enrollment: { maximum: 30, seats_available: 2 } })

      run_task("backfill:seats", "202710")

      expect(first.reload.seats_capacity).to be_nil
      expect(second.reload.seats_capacity).to eq(30)
    end

    it "stops when the term is unknown" do
      expect { run_task("backfill:seats", "999999") }.to raise_error(/not found/)
    end
  end

  describe "backfill:link_identifiers" do
    def catalog(*rows)
      { success: true, courses: rows, total_count: rows.length }
    end

    it "writes the identifier Banner reports" do
      lecture = course(crn: 16861, section_number: "1A")

      allow(LeopardWebService).to receive(:get_course_catalog)
        .with(term: "202710")
        .and_return(catalog(
                      { "courseReferenceNumber" => "16861", "linkIdentifier" => "A1", "isSectionLinked" => true }
                    ))

      run_task("backfill:link_identifiers", "202710")

      lecture.reload
      expect(lecture.link_identifier).to eq("A1")
      expect(lecture.is_section_linked).to be(true)
    end

    it "ignores CRNs that are not in the database" do
      allow(LeopardWebService).to receive(:get_course_catalog).and_return(catalog(
        { "courseReferenceNumber" => "99999", "linkIdentifier" => "A1", "isSectionLinked" => true }
      ))

      expect { run_task("backfill:link_identifiers", "202710") }.not_to change(Course, :count)
    end

    it "does not touch the other columns" do
      lecture = course(crn: 16862, section_number: "1A", seats_capacity: 24, title: "General Chemistry")

      allow(LeopardWebService).to receive(:get_course_catalog).and_return(catalog(
        { "courseReferenceNumber" => "16862", "linkIdentifier" => "A1", "isSectionLinked" => true }
      ))

      run_task("backfill:link_identifiers", "202710")

      lecture.reload
      expect(lecture.seats_capacity).to eq(24)
      expect(lecture.title).to eq("General Chemistry")
    end

    it "reports a failed catalog fetch without raising" do
      course(crn: 16863, section_number: "1A")

      allow(LeopardWebService).to receive(:get_course_catalog)
        .and_return({ success: false, error: "Banner is down", courses: [], total_count: 0 })

      expect { run_task("backfill:link_identifiers", "202710") }.not_to raise_error
      expect(Course.find_by(crn: 16863).link_identifier).to be_nil
    end
  end
end
