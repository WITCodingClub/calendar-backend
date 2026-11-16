# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::Page do
  it "uses the list's default size without a per_page" do
    expect(described_class.new(:courses).per_page).to eq(described_class.default_size(:courses))
  end

  it "clamps per_page to the list's maximum and the page to 1" do
    page = described_class.new(:reviews, page: "-3", per_page: "5000")

    expect([ page.number, page.per_page ]).to eq([ 1, described_class.max_size(:reviews) ])
  end

  it "reads an empty per_page as the default" do
    expect(described_class.new(:sections, per_page: "").per_page).to eq(described_class.default_size(:sections))
  end

  it "uses the smaller MCP sizes for the mcp surface" do
    page = described_class.new(:sections, per_page: 500, surface: :mcp)

    expect(page.per_page).to eq(described_class.max_size(:sections, surface: :mcp))
    expect(described_class.new(:instructors, surface: :mcp).per_page).to eq(10)
  end

  it "builds the meta of a list" do
    expect(described_class.new(:sections, page: 2, per_page: 10).meta(25))
      .to eq(page: 2, per_page: 10, total_count: 25, total_pages: 3)
  end
end
