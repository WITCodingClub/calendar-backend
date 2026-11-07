# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::PdfCatalog::Importer do
  let(:client) { DegreeRequirements::CatalogSiteClient.new(delay: 0, wayback_delay: 0) }
  let(:pdf) { "%PDF-1.4 catalog".b }
  let!(:science) { create(:degree_program, slug: "computer-science-bs", name: "Computer Science, B.S.") }
  let!(:electrical) { create(:degree_program, slug: "electrical-engineering-bs", name: "Electrical Engineering, B.S.") }

  def stub_pdf(start_year, text, body: pdf)
    stub_request(:get, DegreeRequirements::PdfCatalog.url_for(start_year)).to_return(status: 200, body: body)
    # pdftotext is a local program; the fixture is its output.
    allow(DegreeRequirements::PdfCatalog::Text).to receive(:extract).and_return(file_fixture("degree_requirements/pdf/#{text}").read)
  end

  def import(catalog_year) = described_class.new(catalog_year, client: client).call

  context "with a year that has only a PDF" do
    let(:catalog_year) { create(:catalog_year, start_year: 2014) }

    before { stub_pdf(2014, "grid.txt") }

    it "writes a requirement set for each plan it can match, for review" do
      result = import(catalog_year)

      expect(result).to have_attributes(status: :imported, programs: 2, updated: 2, unchanged: 0, unmatched: [])
      set = catalog_year.requirement_sets.find_by!(degree_program: science)
      expect(set).to have_attributes(name: "COMPUTER SCIENCE (BCOS)", source: "pdf", needs_review: true, reviewed_at: nil,
                                     path: "/previous-catalogs/WIT_2014-15_Academic_Catalog_.pdf#page=2", total_credits: 39)
      expect(set.catalog_url).to eq("https://catalog.wit.edu/previous-catalogs/WIT_2014-15_Academic_Catalog_.pdf#page=2")
      expect(set.program_plans.sole).to have_attributes(name: "Computer Science (BCOS)", years: 2)
      expect(set.program_plans.sole.items.count).to eq(11)
    end

    it "marks the year imported from the PDF" do
      import(catalog_year)

      expect(catalog_year.reload).to have_attributes(status: "imported", source: "pdf",
                                                     base_url: DegreeRequirements::PdfCatalog.url_for(2014))
    end

    it "saves the title and credits of each course for the year" do
      import(catalog_year)

      expect(catalog_year.catalog_year_courses.find_by!(subject_code: "COMP", course_number: 128))
        .to have_attributes(title: "Computer Science I", min_credits: 4, max_credits: 4)
    end

    it "keeps a checked set when the PDF did not change" do
      import(catalog_year)
      set = catalog_year.requirement_sets.find_by!(degree_program: science)
      set.update!(needs_review: false, reviewed_at: 1.day.ago)

      expect(import(catalog_year)).to have_attributes(updated: 0, unchanged: 2)
      expect(set.reload.needs_review).to be(false)
    end

    it "writes a changed PDF again and asks for a new review" do
      import(catalog_year)
      set = catalog_year.requirement_sets.find_by!(degree_program: science)
      set.update!(needs_review: false, reviewed_at: 1.day.ago)
      stub_pdf(2014, "grid.txt", body: "%PDF-1.4 changed".b)

      expect(import(catalog_year)).to have_attributes(updated: 2)
      expect(set.reload).to have_attributes(needs_review: true, reviewed_at: nil)
    end

    it "lists the plans with no program and writes nothing for them" do
      electrical.destroy!

      result = import(catalog_year)

      expect(result.unmatched).to eq([ "ELECTRICAL ENGINEERING (BSEE)" ])
      expect(catalog_year.requirement_sets.count).to eq(1)
    end

    it "marks the year failed when no plan matches a program" do
      DegreeProgram.destroy_all
      allow(Rails.error).to receive(:report)

      expect(import(catalog_year).status).to eq(:failed)
      expect(catalog_year.reload.status).to eq("failed")
      expect(Rails.error).to have_received(:report)
    end

    it "marks a year with no PDF missing" do
      stub_request(:get, DegreeRequirements::PdfCatalog.url_for(2014)).to_return(status: 404)

      expect(import(catalog_year).status).to eq(:missing)
      expect(catalog_year.reload.status).to eq("missing")
    end
  end

  context "with 2025-2026, read from the Wayback Machine first" do
    let(:catalog_year) { create(:catalog_year, :imported, start_year: 2025, source: "wayback") }

    before do
      create(:requirement_set, catalog_year: catalog_year, degree_program: electrical, source: "wayback")
      stub_pdf(2025, "courseleaf.txt")
    end

    it "adds the programs with no set, and keeps the year as it was" do
      expect { import(catalog_year) }.to change(RequirementSet, :count).by(1)

      expect(catalog_year.requirement_sets.find_by!(degree_program: science))
        .to have_attributes(source: "pdf", needs_review: true, name: "Computer Science Bachelor of Science")
      expect(catalog_year.reload).to have_attributes(source: "wayback", status: "imported")
      expect(catalog_year.catalog_year_courses).to be_empty
    end

    it "does not replace a set from the Wayback Machine" do
      wayback_set = create(:requirement_set, catalog_year: catalog_year, degree_program: science, source: "wayback")

      expect { import(catalog_year) }.not_to change(RequirementSet, :count)
      expect(wayback_set.reload).to have_attributes(source: "wayback", needs_review: false)
    end
  end

  it "refuses a year with no catalog PDF" do
    expect { import(create(:catalog_year, start_year: 2021)) }.to raise_error(ArgumentError, /no catalog PDF/)
  end
end
