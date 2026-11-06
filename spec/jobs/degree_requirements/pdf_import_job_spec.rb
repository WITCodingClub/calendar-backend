# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::PdfImportJob do
  let(:url) { "https://catalog.wit.edu/previous-catalogs/WIT_2014-15_Academic_Catalog_.pdf" }
  let(:importer) { instance_double(DegreeRequirements::PdfImporter, call: nil) }

  before do
    allow(DegreeRequirements::RequestPacer).to receive(:new).and_return(instance_double(DegreeRequirements::RequestPacer, wait: nil))
    allow(DegreeRequirements::PdfImporter).to receive(:new).and_return(importer)
    allow(FinalsSchedules::PdfText).to receive(:extract).and_return("the text")
  end

  it "downloads the PDF of the year and imports its text" do
    stub_request(:get, url).to_return(status: 200, body: "%PDF-1.7".b)

    described_class.perform_now(2014)

    expect(FinalsSchedules::PdfText).to have_received(:extract).with("%PDF-1.7".b)
    expect(DegreeRequirements::PdfImporter).to have_received(:new).with(CatalogYear.find_by!(start_year: 2014), text: "the text")
    expect(importer).to have_received(:call)
  end

  it "raises for a year with no PDF catalog" do
    expect { described_class.perform_now(2022) }.to raise_error(DegreeRequirements::Error, /no PDF catalog/)
  end

  it "shares the lock of the HTML import" do
    expect(described_class.concurrency_group).to eq(DegreeRequirements::ImportJob.concurrency_group)
    expect(described_class.new(2014).concurrency_key).to eq(DegreeRequirements::ImportJob.new(2024).concurrency_key)
  end
end
