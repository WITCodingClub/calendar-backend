# frozen_string_literal: true

require "rails_helper"

RSpec.describe TermElectives::Importer do
  include ActiveSupport::Testing::TimeHelpers

  subject(:importer) { described_class.new }

  let(:page_url) { TermElectives::PAGE_URL }
  let(:scds_url) { "https://wit.edu/sites/default/files/2031-01/SCDS_Electives_Spring%202031.pdf" }
  let(:hss_url) { "https://wit.edu/sites/default/files/2031-01/Spring%202031%20HSS%20Electives.pdf" }
  let!(:term) { create(:term, year: 2031, season: :spring) }
  let(:texts) do
    {
      "scds-pdf" => file_fixture("term_electives/program_lists.txt").read,
      "hss-pdf"  => file_fixture("term_electives/area_table.txt").read
    }
  end

  before do
    %w[MGMT COMP MATH ECON PHIL].each { |subject| create(:catalog_course, subject_code: subject) }
    stub_request(:get, page_url).to_return(status: 200, body: file_fixture("term_electives/registrar_page.html").read)
    stub_request(:get, scds_url).to_return(status: 200, body: "scds-pdf")
    stub_request(:get, hss_url).to_return(status: 200, body: "hss-pdf")
    # pdftotext is the boundary here, as HTTP is for the requests. CI has no
    # poppler.
    allow(FinalsSchedules::PdfText).to receive(:extract) { |pdf| texts.fetch(pdf) }
  end

  it "imports each PDF that the page links" do
    result = importer.call

    expect(result).to have_attributes(imported: 2, unchanged: 0, skipped: 0, failed: 0, removed: 0)
    scds = TermElectiveList.find_by!(url: scds_url)
    expect(scds).to have_attributes(term: term, school: "SCDS", sha256: Digest::SHA256.hexdigest("scds-pdf"),
                                    title: "Spring 2031 School of Computing and Data Science Electives")
    expect(scds.body_text).to include("Any 2000-Level courses")
    expect(TermElectiveList.find_by!(url: hss_url).school).to eq("HSS")
  end

  it "stores each course with its heading and position, and links it to the catalog" do
    catalog_course = create(:catalog_course, subject_code: "COMP", course_number: 2000)

    importer.call

    courses = TermElectiveList.find_by!(url: scds_url).courses
    expect(courses.first).to have_attributes(subject_code: "MGMT", course_number: 1500, heading: "Domain Electives", position: 0)
    expect(courses.find_by!(subject_code: "COMP", course_number: 2000).catalog_course).to eq(catalog_course)
  end

  it "drops a code whose subject Banner does not know" do
    importer.call

    expect(TermElectiveCourse.where(subject_code: "PHYS")).to be_empty
  end

  it "skips a PDF that did not change" do
    importer.call

    result = importer.call

    expect(result).to have_attributes(imported: 0, unchanged: 2)
    expect(FinalsSchedules::PdfText).to have_received(:extract).twice
  end

  it "only fetches PDF links over HTTPS on wit.edu, once for each file" do
    importer.call

    expect(TermElectiveList.pluck(:url)).to contain_exactly(scds_url, hss_url)
    expect(a_request(:get, scds_url)).to have_been_made.once
    expect(a_request(:get, "http://wit.edu/sites/default/files/plain.pdf")).not_to have_been_made
  end

  it "adds the courses of a subject that Banner adds after the import" do
    importer.call
    create(:catalog_course, subject_code: "PHYS", course_number: 1250)

    importer.call

    course = TermElectiveCourse.find_by!(subject_code: "PHYS")
    expect(course).to have_attributes(heading: "Lab-based Science Electives (BSCN, BSCO)", catalog_course: CatalogCourse.find_by!(subject_code: "PHYS"))
    expect(FinalsSchedules::PdfText).to have_received(:extract).twice
  end

  it "keeps the rows of an unchanged PDF when nothing else changed, and records the read" do
    importer.call
    ids = TermElectiveCourse.ids

    travel_to(1.day.from_now) { importer.call }

    expect(TermElectiveCourse.ids).to match_array(ids)
    expect(TermElectiveList.find_by!(url: scds_url).fetched_at).to be > 12.hours.from_now
  end

  it "links a course to a catalog course that Banner adds after the import" do
    importer.call
    course = TermElectiveCourse.find_by!(subject_code: "COMP", course_number: 2000)
    catalog_course = create(:catalog_course, subject_code: "COMP", course_number: 2000)

    importer.call

    expect(course.reload.catalog_course).to eq(catalog_course)
  end

  it "writes the courses again when a PDF changed" do
    importer.call
    texts["scds-pdf v2"] = "Spring 2031 Electives\nNET Elective\n• COMP3400 – Operating Systems\n"
    stub_request(:get, scds_url).to_return(status: 200, body: "scds-pdf v2")

    expect(importer.call).to have_attributes(imported: 1, unchanged: 1)

    courses = TermElectiveList.find_by!(url: scds_url).courses
    expect(courses.map(&:code)).to eq([ "COMP 3400" ])
  end

  it "skips a missing PDF and a PDF for a term that is not stored" do
    stub_request(:get, scds_url).to_return(status: 404)
    texts["hss-pdf"] = "Fall 2040 Electives\nNET Elective\n• COMP3400 – Operating Systems\n"

    expect(importer.call).to have_attributes(imported: 0, skipped: 2)
    expect(TermElectiveList.count).to eq(0)
  end

  it "removes a list of a term on the page whose file left the page" do
    old = create(:term_elective_list, term: term, url: "https://wit.edu/sites/default/files/2031-01/SCDS_V1.pdf")
    other_term = create(:term_elective_list)

    expect(importer.call.removed).to eq(1)

    expect(TermElectiveList.exists?(old.id)).to be(false)
    expect(TermElectiveList.exists?(other_term.id)).to be(true)
  end

  it "reports a PDF that fails and imports the others" do
    allow(Rails.error).to receive(:report)
    stub_request(:get, scds_url).to_return(status: 500)

    expect(importer.call).to have_attributes(imported: 1, failed: 1)
    expect(Rails.error).to have_received(:report)
      .with(an_instance_of(TermElectives::FetchError), handled: true, context: { url: scds_url })
  end

  it "reports a PDF that fails to save and imports the others" do
    allow(Rails.error).to receive(:report)
    allow(TermElectiveList).to receive(:new).and_call_original
    allow(TermElectiveList).to receive(:new).with(url: scds_url).and_raise(ActiveRecord::RecordNotUnique)

    expect(importer.call).to have_attributes(imported: 1, failed: 1)
    expect(Rails.error).to have_received(:report)
      .with(an_instance_of(ActiveRecord::RecordNotUnique), handled: true, context: { url: scds_url })
  end

  it "reports a PDF with a bad redirect and imports the others" do
    allow(Rails.error).to receive(:report)
    stub_request(:get, scds_url).to_return(status: 301, headers: { "Location" => "/files/a b\u2013c.pdf" })

    expect(importer.call).to have_attributes(imported: 1, failed: 1)
    expect(Rails.error).to have_received(:report).with(an_instance_of(TermElectives::FetchError), handled: true, context: { url: scds_url })
  end

  it "escapes a link with a character that is not ASCII" do
    page = "<a href=\"/files/HSS \u2013 Spring.pdf\">HSS</a>"
    stub_request(:get, page_url).to_return(status: 200, body: page)
    stub_request(:get, "https://wit.edu/files/HSS%20%E2%80%93%20Spring.pdf").to_return(status: 404)

    expect(importer.call).to have_attributes(skipped: 1)
  end

  it "reports a page that links no PDF, and removes nothing" do
    allow(Rails.error).to receive(:report)
    list = create(:term_elective_list, term: term)
    stub_request(:get, page_url).to_return(status: 200, body: "<p>Moved</p>")

    expect(importer.call.removed).to eq(0)
    expect(TermElectiveList.exists?(list.id)).to be(true)
    expect(Rails.error).to have_received(:report).with(an_instance_of(TermElectives::Error), handled: true)
  end

  it "raises when the page is missing" do
    stub_request(:get, page_url).to_return(status: 404)

    expect { importer.call }.to raise_error(TermElectives::FetchError, /not found/)
  end
end
