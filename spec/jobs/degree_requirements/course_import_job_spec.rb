# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::CourseImportJob do
  let(:importer) { instance_double(DegreeRequirements::CourseImporter, call: 3) }

  before { allow(DegreeRequirements::CourseImporter).to receive(:new).and_return(importer) }

  it "imports the courses of the catalog year" do
    catalog_year = create(:catalog_year, start_year: 2024)

    expect(described_class.perform_now(2024)).to eq(3)
    expect(DegreeRequirements::CourseImporter).to have_received(:new).with(catalog_year)
  end

  it "does nothing for a catalog year that is not stored" do
    described_class.perform_now(2030)

    expect(DegreeRequirements::CourseImporter).not_to have_received(:new)
  end
end
