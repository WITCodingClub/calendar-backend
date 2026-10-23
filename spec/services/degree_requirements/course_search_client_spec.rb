# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::CourseSearchClient do
  subject(:client) { described_class.new(delay: 0) }

  let(:search_url) { "https://catalog.wit.edu/course-search/api/?page=fose&route=search" }
  let(:details_url) { "https://catalog.wit.edu/course-search/api/?page=fose&route=details" }

  it "lists the courses of a catalog year" do
    stub_request(:post, search_url)
      .with(body: { other: { srcdb: "2024" }, criteria: [] }.to_json)
      .to_return(status: 200, body: file_fixture("degree_requirements/course_search.json").read)

    expect(client.search(2024).pluck("code")).to eq(%w[WDGT1000 WDGT3000 SPECIAL])
  end

  it "returns no courses for a year the course search does not have" do
    stub_request(:post, search_url).to_return(status: 200, body: "[]")

    expect(client.search(2015)).to eq([])
  end

  it "reads one course" do
    stub_request(:post, details_url)
      .with(body: hash_including("group" => "code:WDGT3000", "srcdb" => "2024"))
      .to_return(status: 200, body: file_fixture("degree_requirements/course_details_wdgt3000.json").read)

    expect(client.details(2024, "WDGT3000")).to include("code" => "WDGT3000", "title" => "SPINNING &amp; TURNING")
  end

  it "returns nil for a course the year does not have" do
    stub_request(:post, details_url).to_return(status: 200, body: "[]")

    expect(client.details(2019, "WDGT128")).to be_nil
  end

  it "raises a fetch error for a server error or a body that is not JSON" do
    stub_request(:post, search_url).to_return(status: 500).then.to_return(status: 200, body: "<html>")

    expect { client.search(2024) }.to raise_error(DegreeRequirements::FetchError, /HTTP 500/)
    expect { client.search(2024) }.to raise_error(DegreeRequirements::FetchError, /search/)
  end
end
