# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::CourseImporter do
  let(:catalog_year) { create(:catalog_year, start_year: 2024) }
  let(:client) { DegreeRequirements::CourseSearchClient.new(delay: 0) }
  let(:details_url) { "https://catalog.wit.edu/course-search/api/?page=fose&route=details" }

  before do
    stub_request(:post, "https://catalog.wit.edu/course-search/api/?page=fose&route=search")
      .to_return(status: 200, body: file_fixture("degree_requirements/course_search.json").read)
    stub_request(:post, details_url).with(body: hash_including("group" => "code:WDGT1000"))
                                    .to_return(status: 200, body: "[]")
    stub_request(:post, details_url).with(body: hash_including("group" => "code:WDGT3000"))
                                    .to_return(status: 200, body: file_fixture("degree_requirements/course_details_wdgt3000.json").read)
  end

  def import = described_class.new(catalog_year, client: client).call

  it "stores each course of the year with its parts" do
    expect(import).to eq(2)

    course = CatalogYearCourse.find_by!(catalog_year: catalog_year, subject_code: "WDGT", course_number: 3000)
    expect(course).to have_attributes(title: "SPINNING & TURNING", min_credits: 3, max_credits: 4,
                                      prerequisite_text: "WDGT1000 (4 credits) and WDGT2000",
                                      typically_offered: %w[fall spring])
  end

  it "keeps the title from the list when the course has no details" do
    import

    expect(CatalogYearCourse.find_by!(course_number: 1000)).to have_attributes(title: "WIDGETS I", description: nil)
  end

  it "skips a code that is not a course code" do
    import

    expect(CatalogYearCourse.pluck(:subject_code).uniq).to eq([ "WDGT" ])
  end

  it "updates the stored rows on a second import, and links the Banner course" do
    banner = create(:catalog_course, subject_code: "WDGT", course_number: 3000)
    create(:catalog_year_course, catalog_year: catalog_year, subject_code: "WDGT", course_number: 3000, title: "OLD")

    import

    course = CatalogYearCourse.find_by!(course_number: 3000)
    expect(course).to have_attributes(title: "SPINNING & TURNING", catalog_course: banner)
    expect(CatalogYearCourse.count).to eq(2)
  end
end
