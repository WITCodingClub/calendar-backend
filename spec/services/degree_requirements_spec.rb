# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements do
  describe ".page_url" do
    it "links to the catalog site" do
      set = build(:requirement_set, path: "/previous-catalogs/2024-2025/widgetry/widget-design-bs/")

      expect(described_class.page_url(set)).to eq("https://catalog.wit.edu/previous-catalogs/2024-2025/widgetry/widget-design-bs/")
    end

    it "links to the Wayback capture for a year read from the Wayback Machine" do
      set = build(:requirement_set, source: "wayback", path: "/widgetry/widget-design-bs/",
                                    catalog_year: build(:catalog_year, start_year: 2025))

      expect(described_class.page_url(set))
        .to eq("https://web.archive.org/web/20260301000000/https://catalog.wit.edu/widgetry/widget-design-bs/")
    end

    it "is nil with no path" do
      expect(described_class.page_url(build(:requirement_set, path: nil))).to be_nil
    end
  end

  it "gives the saved page of a Wayback capture for the import" do
    expect(described_class.wayback_url(2025, "/programs-az/", raw: true))
      .to eq("https://web.archive.org/web/20260301000000id_/https://catalog.wit.edu/programs-az/")
  end
end
