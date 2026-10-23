# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::CatalogSource do
  let(:client) { DegreeRequirements::CatalogSiteClient.new(delay: 0, wayback_delay: 0) }

  def index_page(span) = "<html><body>Programs<footer>Boston, MA #{span}</footer></body></html>"

  describe ".locate" do
    it "finds an archived year" do
      stub_request(:get, "https://catalog.wit.edu/previous-catalogs/2024-2025/programs-az/")
        .to_return(status: 200, body: index_page("2024-2025"))

      source = described_class.locate(2024, client: client)

      expect(source).to have_attributes(kind: :archive, home_path: "/previous-catalogs/2024-2025/",
                                        catalog_year_source: "html",
                                        base_url: "https://catalog.wit.edu/previous-catalogs/2024-2025/")
      expect(source.index_html).to include("2024-2025")
    end

    it "finds the year the current site shows" do
      stub_request(:get, "https://catalog.wit.edu/previous-catalogs/2026-2027/programs-az/").to_return(status: 404)
      stub_request(:get, "https://catalog.wit.edu/programs-az/").to_return(status: 200, body: index_page("2026-2027"))

      expect(described_class.locate(2026, client: client)).to have_attributes(kind: :current, home_path: "/")
    end

    it "uses the Wayback Machine for a year with no archive" do
      stub_request(:get, "https://catalog.wit.edu/previous-catalogs/2025-2026/programs-az/").to_return(status: 404)
      stub_request(:get, "https://catalog.wit.edu/programs-az/").to_return(status: 200, body: index_page("2026-2027"))
      stub_request(:get, "https://web.archive.org/web/20260301000000id_/https://catalog.wit.edu/programs-az/")
        .to_return(status: 302, headers: { "Location" => "/web/20260301135425id_/https://catalog.wit.edu/programs-az/" })
      stub_request(:get, "https://web.archive.org/web/20260301135425id_/https://catalog.wit.edu/programs-az/")
        .to_return(status: 200, body: index_page("2025-2026"))

      source = described_class.locate(2025, client: client)

      expect(source).to have_attributes(kind: :wayback, catalog_year_source: "wayback")
      expect(source.url_for("/widgetry/widget-design-bs/"))
        .to eq("https://web.archive.org/web/20260301000000id_/https://catalog.wit.edu/widgetry/widget-design-bs/")
    end

    it "returns nil when no place has the year, such as a year not published yet" do
      stub_request(:get, "https://catalog.wit.edu/previous-catalogs/2030-2031/programs-az/").to_return(status: 404)
      stub_request(:get, "https://catalog.wit.edu/programs-az/").to_return(status: 200, body: index_page("2026-2027"))

      expect(described_class.locate(2030, client: client)).to be_nil
    end
  end

  it "reads the catalog year a page names" do
    expect(described_class.page_start_year(index_page("2019-2020"))).to eq(2019)
    expect(described_class.page_start_year("no mark")).to be_nil
  end
end
