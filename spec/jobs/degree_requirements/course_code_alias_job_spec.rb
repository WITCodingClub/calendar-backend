# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::CourseCodeAliasJob do
  let(:base) { "https://catalog.wit.edu/previous-catalogs" }
  let(:finder) { instance_double(DegreeRequirements::CourseCodeAliasFinder, call: :result) }

  before do
    allow(DegreeRequirements::RequestPacer).to receive(:new).and_return(instance_double(DegreeRequirements::RequestPacer, wait: nil))
    allow(DegreeRequirements::CourseCodeAliasFinder).to receive(:new).and_return(finder)
    allow(FinalsSchedules::PdfText).to receive(:extract) { |pdf| "text of #{pdf}" }
  end

  it "reads the 2014-2015 and 2015-2016 catalogs and finds the aliases" do
    stub_request(:get, "#{base}/WIT_2014-15_Academic_Catalog_.pdf").to_return(status: 200, body: "old")
    stub_request(:get, "#{base}/WIT_2015-2016_Academic_Catalog.pdf").to_return(status: 200, body: "new")

    expect(described_class.perform_now).to eq(:result)
    expect(DegreeRequirements::CourseCodeAliasFinder).to have_received(:new)
      .with(texts: { 2014 => "text of old", 2015 => "text of new" })
  end

  it "retries when a PDF is missing" do
    stub_request(:get, "#{base}/WIT_2014-15_Academic_Catalog_.pdf").to_return(status: 404)

    expect { described_class.perform_now }.to have_enqueued_job(described_class)
  end
end
