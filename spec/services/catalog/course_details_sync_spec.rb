# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::CourseDetailsSync do
  include ActiveSupport::Testing::TimeHelpers

  let(:term) { create(:term, uid: 202720, year: 2027, season: :spring) }

  def fixture(name) = file_fixture("leopard_web/#{name}.html").read

  def stub_banner(crn, prerequisites: fixture("prerequisites_and_or_groups"), status: 200)
    {
      "getCourseDescription"    => fixture("course_description"),
      "getSectionPrerequisites" => prerequisites,
      "getCorequisites"         => fixture("corequisites_none"),
      "getRestrictions"         => fixture("restrictions")
    }.each do |path, body|
      stub_request(:get, "#{Catalog::LeopardWebClient::BASE_URL}#{path}")
        .with(query: { term: term.uid.to_s, courseReferenceNumber: crn.to_s })
        .to_return(status: status, body: body)
    end
  end

  def sync = described_class.new(term, pause: 0).call

  let!(:section) { create(:course, term: term, subject: "Computer Science (COMP)", course_number: 2000, crn: 20382, title: "Data Structures") }

  it "stores the details of each course once, from one section" do
    create(:course, term: term, subject: "Computer Science (COMP)", course_number: 2000, crn: 20383)
    stub_banner(20382)

    result = sync

    expect(result).to have_attributes(fetched: 1, skipped: 0, failed: 0)
    course = CatalogCourse.find_by_code("COMP 2000")
    expect(course).to have_attributes(title: "Data Structures", credit_hours: 4, typically_offered: %w[fall spring], source_term: term)
    expect(course.description).to start_with("This course is an introduction")
    expect(course.prerequisites["type"]).to eq("and")
    expect(course.restrictions.size).to eq(2)
    expect(course.corequisites).to eq([])
  end

  it "links each prerequisite to a course in the system, and keeps unknown codes unlinked" do
    known = create(:catalog_course, subject_code: "COMP", course_number: 1050)
    stub_banner(20382)

    sync

    links = CatalogCourse.find_by_code("COMP 2000").course_prerequisites.order(:required_course_number)
    expect(links.map { |l| [ l.required_subject_code, l.required_course_number, l.required_catalog_course_id ] })
      .to eq([ [ "COMP", 1050, known.id ], [ "COMP", 1071, nil ], [ "MATH", 2300, nil ] ])
    expect(known.unlocks.map(&:code)).to eq([ "COMP 2000" ])
  end

  it "links the old prerequisite rows when a later seed adds the course" do
    stub_banner(20382)
    sync

    described_class.seed(Course.where(id: create(:course, subject: "Mathematics (MATH)", course_number: 2300).id))

    expect(CoursePrerequisite.find_by(required_course_number: 2300).required_catalog_course).to eq(CatalogCourse.find_by_code("MATH 2300"))
  end

  it "skips a course fetched for this term in the last week, and fetches it again after that" do
    stub_banner(20382)
    sync

    expect(sync).to have_attributes(fetched: 0, skipped: 1)
    travel(8.days) { expect(sync).to have_attributes(fetched: 1, skipped: 0) }
  end

  it "never replaces details from a newer term" do
    newer = create(:term, uid: 202730, year: 2027, season: :summer)
    create(:catalog_course, subject_code: "COMP", course_number: 2000, source_term: newer, details_fetched_at: 1.year.ago)

    expect(sync).to have_attributes(fetched: 0, skipped: 1)
  end

  it "keeps the old details and reports the error when Banner fails" do
    course = create(:catalog_course, subject_code: "COMP", course_number: 2000, description: "Old text")
    stub_banner(20382, status: 500)

    reports = capture_error_reports { expect(sync).to have_attributes(failed: 1) }

    expect(course.reload.description).to eq("Old text")
    expect(reports.first.context).to include(catalog_course_id: course.id, crn: 20382)
  end

  it "seeds a row for every course with the newest title" do
    old_term = create(:term, uid: 202620, year: 2026, season: :spring)
    create(:course, term: old_term, subject: "Mathematics (MATH)", course_number: 2860, title: "Old Name")
    create(:course, term: term, subject: "Mathematics (MATH)", course_number: 2860, title: "Linear Algebra")

    expect(described_class.seed(Course.all)).to eq(2)
    expect(CatalogCourse.find_by_code("MATH 2860").title).to eq("Linear Algebra")
    expect(described_class.seed(Course.none)).to eq(0)
  end

  it "reads the subject code from either spelling" do
    expect(described_class.prefix_of("Computer Science (COMP)")).to eq("COMP")
    expect(described_class.prefix_of("comp")).to eq("COMP")
  end
end
