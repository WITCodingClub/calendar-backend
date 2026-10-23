# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::ImportJob do
  let(:importer) { instance_double(DegreeRequirements::Importer) }

  def result(status) = DegreeRequirements::Importer::Result.new(status: status, programs: 0, updated: 0, unchanged: 0, skipped: 0)

  before { allow(DegreeRequirements::Importer).to receive(:new).and_return(importer) }

  it "creates the catalog year, imports it, and queues the course import" do
    allow(importer).to receive(:call).and_return(result(:imported))

    expect { described_class.perform_now(2024) }.to have_enqueued_job(DegreeRequirements::CourseImportJob).with(2024)
    expect(DegreeRequirements::Importer).to have_received(:new).with(CatalogYear.find_by!(start_year: 2024))
  end

  it "queues no course import for a missing year" do
    allow(importer).to receive(:call).and_return(result(:missing))

    expect { described_class.perform_now(2030) }.not_to have_enqueued_job(DegreeRequirements::CourseImportJob)
  end

  it "marks the year failed when the import raises" do
    allow(importer).to receive(:call).and_raise(DegreeRequirements::ImportShrankError, "short")

    expect { described_class.perform_now(2024) }.to raise_error(DegreeRequirements::ImportShrankError)
    expect(CatalogYear.find_by!(start_year: 2024).status).to eq("failed")
  end

  it "retries a fetch error" do
    allow(importer).to receive(:call).and_raise(DegreeRequirements::FetchError, "HTTP 503")

    expect { described_class.perform_now(2024) }.to have_enqueued_job(described_class).with(2024)
  end
end
