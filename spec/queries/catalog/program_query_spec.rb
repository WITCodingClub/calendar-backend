# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::ProgramQuery do
  describe ".start_year" do
    {
      "2024"         => 2024,
      2024           => 2024,
      "2024-2025"    => 2024,
      "2024 - 2025"  => 2024,
      "2024-25"      => 2024,
      "2024–2025"    => 2024,
      "2099-00"      => 2099,
      "Fall 2023"    => 2023,
      "spring 2024"  => 2023,
      "Summer 2024"  => 2023,
      "2024-2030"    => nil,
      "2024-26"      => nil,
      "Winter 2024"  => nil,
      "last year"    => nil,
      ""             => nil
    }.each do |value, start_year|
      it "reads #{value.inspect} as #{start_year.inspect}" do
        expect(described_class.start_year(value)).to eq(start_year)
      end
    end
  end

  describe "#catalog_year" do
    let!(:older) { create(:catalog_year, :imported, start_year: 2023) }
    let!(:newer) { create(:catalog_year, :imported, start_year: 2024) }

    before { create(:catalog_year, start_year: 2025) }

    it "gives the newest imported year without a value, and the year of a term name" do
      expect(described_class.new.catalog_year(nil)).to eq(newer)
      expect(described_class.new.catalog_year("Spring 2024")).to eq(older)
      expect(described_class.new.catalog_year("2025-2026")).to be_nil
    end

    it "raises a filter error for a value that is not a catalog year" do
      expect { described_class.new.catalog_year("2024-2030") }
        .to raise_error(described_class::InvalidCatalogYearError, /Spring 2024/) { |error| expect(error.code).to eq("invalid_catalog_year") }
    end

    it "names the imported years when catalog_year! finds none" do
      expect { described_class.new.catalog_year!("2025-2026") }
        .to raise_error(described_class::UnknownCatalogYearError, "No 2025-2026 catalog. WIT Calendar has these catalog years: 2024-2025, 2023-2024.") { |error|
          expect(error.code).to eq("unknown_catalog_year")
        }
    end
  end

  it "says catalog_year! has no data before an import" do
    expect { described_class.new.catalog_year!(nil) }
      .to raise_error(described_class::UnknownCatalogYearError, "WIT Calendar has no degree program data yet.")
  end

  describe "#call and #find" do
    let(:catalog_year) { create(:catalog_year, :imported, start_year: 2024) }
    let!(:dropped) do
      create(:requirement_set, :unlisted, catalog_year: catalog_year,
                                          degree_program: create(:degree_program, slug: "old-widgets-bs"))
    end

    before { create(:requirement_set, catalog_year: catalog_year, degree_program: create(:degree_program, slug: "widgets-bs")) }

    it "lists only the programs the last import saw, but still finds a dropped one" do
      expect(described_class.new.call(catalog_year: catalog_year).map { |set| set.degree_program.slug }).to eq(%w[widgets-bs])
      expect(described_class.new.find("OLD-WIDGETS-BS", catalog_year: catalog_year)).to eq(dropped)
    end

    it "raises a not found error with a code when find! finds no program" do
      expect(described_class.new.find!("widgets-bs", catalog_year: catalog_year).degree_program.slug).to eq("widgets-bs")
      expect { described_class.new.find!("gears-bs", catalog_year: catalog_year) }
        .to raise_error(described_class::UnknownProgramError, "No program gears-bs in the 2024-2025 catalog") { |error|
          expect(error).to be_a(described_class::NotFoundError)
          expect(error.code).to eq("unknown_program")
        }
    end

    it "finds a renamed program by its old slug" do
      renamed = create(:requirement_set, catalog_year: catalog_year,
                                         degree_program: create(:degree_program, slug: "biological-engineering-bs"))

      expect(described_class.new.find("biological-engineering-program", catalog_year: catalog_year)).to eq(renamed)
    end

    it "lists the concentrations of a major, and rejects a slug that is no program" do
      major = DegreeProgram.find_by!(slug: "widgets-bs")
      concentration = create(:degree_program, :concentration, parent_program: major, slug: "widgets-bs-gears")
      create(:requirement_set, catalog_year: catalog_year, degree_program: concentration)
      create(:requirement_set, catalog_year: catalog_year, degree_program: create(:degree_program, :concentration))

      expect(described_class.new.call(catalog_year: catalog_year, parent: "Widgets-BS").map { |set| set.degree_program.slug })
        .to eq(%w[widgets-bs-gears])
      expect { described_class.new.call(catalog_year: catalog_year, parent: "no-such-bs") }
        .to raise_error(Catalog::FilterError, /parent_program/)
    end
  end
end
