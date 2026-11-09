# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::SubjectLabelRepair do
  let(:term) { create(:term, uid: 202710, year: 2026, season: :fall) }

  before do
    stub_request(:get, %r{\Ahttps://selfservice\.wit\.edu/StudentRegistrationSsb/ssb/classSearch/get_subject})
      .with(query: hash_including("term" => "202710"))
      .to_return(status: 200, body: file_fixture("leopard_web/subjects.json").read,
                 headers: { "Content-Type" => "application/json" })
  end

  it "adds the code to labels without one, and labels bare codes" do
    resilience = create(:course, term: term, subject: "Climate Resilience", course_number: 1000)
    internship = create(:course, term: term, subject: "Graduate Internship (optional)", course_number: 6000)
    bare = create(:course, term: term, subject: "COMP", course_number: 2000)
    labeled = create(:course, term: term, subject: "Computer Science (COMP)", course_number: 1000)

    result = described_class.call

    expect(result[:sections]).to eq(3)
    expect(resilience.reload.subject).to eq("Climate Resilience (CRES)")
    expect(internship.reload.subject).to eq("Graduate Internship (optional) (INTN)")
    expect(bare.reload.subject).to eq("Computer Science (COMP)")
    expect(labeled.reload.subject).to eq("Computer Science (COMP)")
  end

  it "moves a catalog course seeded under the label to the code, keeping its details" do
    create(:course, term: term, subject: "Climate Resilience", course_number: 1000)
    catalog = create(:catalog_course, subject_code: "CLIMATE RESILIENCE", course_number: 1000, description: "Boston.")

    expect(described_class.call[:catalog_courses_moved]).to eq(1)
    expect(catalog.reload).to have_attributes(subject_code: "CRES", description: "Boston.")
  end

  it "moves the row the old reader named by the last parentheses" do
    create(:course, term: term, subject: "Graduate Internship (optional)", course_number: 6000)
    catalog = create(:catalog_course, subject_code: "OPTIONAL", course_number: 6000)

    described_class.call

    expect(catalog.reload.subject_code).to eq("INTN")
  end

  it "moves a course seeded under the wrong code in Banner's label" do
    section = create(:course, term: term, subject: "Facilities Management (CPCE)", course_number: 5500)
    catalog = create(:catalog_course, subject_code: "CPCE", course_number: 5500)

    described_class.call

    expect(section.reload.subject).to eq("Facilities Management (CPFM)")
    expect(catalog.reload.subject_code).to eq("CPFM")
  end

  it "deletes the row under the label when the code already has one" do
    create(:course, term: term, subject: "Building Construction", course_number: 1100)
    create(:catalog_course, subject_code: "BUILDING CONSTRUCTION", course_number: 1100)
    real = create(:catalog_course, subject_code: "BLDG", course_number: 1100)

    expect(described_class.call[:catalog_courses_merged]).to eq(1)
    expect(CatalogCourse.where(course_number: 1100)).to eq([ real ])
  end

  it "links catalog year courses to the moved row" do
    create(:course, term: term, subject: "Climate Resilience", course_number: 1000)
    catalog = create(:catalog_course, subject_code: "CLIMATE RESILIENCE", course_number: 1000)
    year_course = create(:catalog_year_course, subject_code: "CRES", course_number: 1000, catalog_course: nil)

    described_class.call

    expect(year_course.reload.catalog_course).to eq(catalog)
  end
end
