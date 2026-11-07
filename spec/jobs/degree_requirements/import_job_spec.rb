# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::ImportJob do
  let(:importer) { instance_double(DegreeRequirements::Importer) }

  def result(status) = DegreeRequirements::Importer::Result.new(status: status, programs: 0, updated: 0, unchanged: 0, skipped: 0)

  before { allow(DegreeRequirements::Importer).to receive(:new).and_return(importer) }

  it "creates the catalog year, imports it, and queues the course import" do
    allow(importer).to receive(:call).and_return(result(:imported))

    expect { described_class.perform_now(2024) }.to have_enqueued_job(DegreeRequirements::CourseImportJob).with(2024)
    expect(DegreeRequirements::Importer).to have_received(:new).with(CatalogYear.find_by!(start_year: 2024), force: false)
  end

  it "passes force on to the importer" do
    allow(importer).to receive(:call).and_return(result(:imported))

    described_class.perform_now(2024, force: true)

    expect(DegreeRequirements::Importer).to have_received(:new).with(an_instance_of(CatalogYear), force: true)
  end

  context "with a catalog PDF" do
    let(:pdf_importer) { instance_double(DegreeRequirements::PdfCatalog::Importer) }
    let(:pdf_result) do
      DegreeRequirements::PdfCatalog::Importer::Result.new(status: :imported, programs: 0, updated: 0, unchanged: 0, unmatched: [])
    end

    before do
      allow(DegreeRequirements::PdfCatalog::Importer).to receive(:new).and_return(pdf_importer)
      allow(pdf_importer).to receive(:call).and_return(pdf_result)
    end

    it "imports a year before 2019-2020 from its PDF only, with no course import" do
      expect { described_class.perform_now(2014) }.not_to have_enqueued_job(DegreeRequirements::CourseImportJob)
      expect(DegreeRequirements::PdfCatalog::Importer).to have_received(:new).with(CatalogYear.find_by!(start_year: 2014))
      expect(DegreeRequirements::Importer).not_to have_received(:new)
    end

    it "fills 2025-2026 from its PDF after the Wayback Machine" do
      allow(importer).to receive(:call).and_return(result(:imported))

      expect { described_class.perform_now(2025) }.to have_enqueued_job(DegreeRequirements::CourseImportJob).with(2025)
      expect(pdf_importer).to have_received(:call)
    end

    it "reports a failed PDF fill and keeps the course import" do
      allow(importer).to receive(:call).and_return(result(:imported))
      allow(pdf_importer).to receive(:call).and_raise(DegreeRequirements::Error, "bad PDF")
      allow(Rails.error).to receive(:report)

      expect { described_class.perform_now(2025) }.to have_enqueued_job(DegreeRequirements::CourseImportJob).with(2025)
      expect(Rails.error).to have_received(:report).with(an_instance_of(DegreeRequirements::Error), handled: true,
                                                                                                   context: hash_including(:catalog_year_id))
    end

    it "reads no PDF for a year with an HTML archive" do
      allow(importer).to receive(:call).and_return(result(:imported))

      described_class.perform_now(2024)

      expect(DegreeRequirements::PdfCatalog::Importer).not_to have_received(:new)
    end
  end

  it "runs one import at a time for every year" do
    expect(described_class.concurrency_key).to be_present
    expect(described_class.new(2019).concurrency_key).to eq(described_class.new(2024).concurrency_key)
  end

  it "queues no course import for a missing year" do
    allow(importer).to receive(:call).and_return(result(:missing))

    expect { described_class.perform_now(2030) }.not_to have_enqueued_job(DegreeRequirements::CourseImportJob)
  end

  it "marks a year with no data failed when the import raises" do
    allow(importer).to receive(:call).and_raise(ArgumentError, "bad index")

    expect { described_class.perform_now(2024) }.to raise_error(ArgumentError)
    expect(CatalogYear.find_by!(start_year: 2024).status).to eq("failed")
  end

  it "keeps the status of a year with data when the import raises" do
    catalog_year = create(:catalog_year, :imported, start_year: 2024)
    create(:requirement_set, catalog_year: catalog_year)
    allow(importer).to receive(:call).and_raise(DegreeRequirements::ImportShrankError, "short")

    expect { described_class.perform_now(2024) }.to raise_error(DegreeRequirements::ImportShrankError)
    expect(catalog_year.reload.status).to eq("imported")
  end

  it "retries a fetch error" do
    allow(importer).to receive(:call).and_raise(DegreeRequirements::FetchError, "HTTP 503")

    expect { described_class.perform_now(2024) }.to have_enqueued_job(described_class).with(2024)
  end
end
