# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::LeopardWebClient, ".get_course_details" do
  let(:base) { described_class::BASE_URL }

  def stub_page(path, body: "<section>#{path}</section>", status: 200)
    stub_request(:get, "#{base}#{path}").with(query: { term: "202720", courseReferenceNumber: "20382" })
                                        .to_return(status: status, body: body, headers: { "Content-Type" => "text/html" })
  end

  it "returns the HTML of each page" do
    described_class::COURSE_DETAIL_PAGES.each_value { |path| stub_page(path) }

    pages = described_class.get_course_details(term: 202720, course_reference_number: 20382)

    expect(pages.keys).to eq(%i[description prerequisites corequisites restrictions catalog mutual_exclusions fees syllabus])
    expect(pages[:prerequisites]).to eq("<section>getSectionPrerequisites</section>")
    expect(pages[:syllabus]).to eq("<section>getSyllabus</section>")
  end

  it "raises a request error when Banner does not answer 200" do
    stub_page("getCourseDescription", status: 500)

    expect { described_class.get_course_details(term: 202720, course_reference_number: 20382) }
      .to raise_error(described_class::RequestError, /getCourseDescription answered 500/)
  end

  it "needs a term and a CRN" do
    expect { described_class.get_course_details(term: nil, course_reference_number: 1) }.to raise_error(ArgumentError)
    expect { described_class.get_course_details(term: 1, course_reference_number: nil) }.to raise_error(ArgumentError)
  end
end
