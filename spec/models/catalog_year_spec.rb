# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: catalog_years
#
#  id          :bigint           not null, primary key
#  base_url    :string
#  imported_at :datetime
#  source      :string           default("html"), not null
#  start_year  :integer          not null
#  status      :string           default("pending"), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_catalog_years_on_start_year  (start_year) UNIQUE
#
RSpec.describe CatalogYear do
  subject { create(:catalog_year) }

  it { is_expected.to have_many(:requirement_sets).dependent(:destroy) }
  it { is_expected.to have_many(:degree_programs).through(:requirement_sets) }
  it { is_expected.to have_many(:catalog_year_courses).dependent(:delete_all) }
  it { is_expected.to validate_presence_of(:start_year) }
  it { is_expected.to validate_uniqueness_of(:start_year) }
  it { is_expected.to validate_numericality_of(:start_year).only_integer.is_greater_than_or_equal_to(2010) }

  it do
    expect(subject).to define_enum_for(:source).with_values(html: "html", wayback: "wayback", pdf: "pdf")
                                               .backed_by_column_of_type(:string).with_prefix.validating
  end

  it do
    expect(subject).to define_enum_for(:status)
      .with_values(pending: "pending", imported: "imported", missing: "missing", failed: "failed")
      .backed_by_column_of_type(:string).validating
  end

  it "names the year span" do
    expect(build(:catalog_year, start_year: 2024).name).to eq("2024-2025")
  end

  describe ".for_term" do
    let!(:catalog_year) { create(:catalog_year, start_year: 2026) }

    it "puts a fall term in the catalog year that starts that fall" do
      expect(described_class.for_term(build(:term, year: 2026, season: :fall))).to eq(catalog_year)
    end

    it "puts spring and summer terms in the catalog year that started the fall before" do
      expect(described_class.for_term(build(:term, year: 2027, season: :spring))).to eq(catalog_year)
      expect(described_class.for_term(build(:term, year: 2027, season: :summer))).to eq(catalog_year)
    end

    it "returns nil when the catalog year is not stored" do
      expect(described_class.for_term(build(:term, year: 2030, season: :fall))).to be_nil
    end
  end
end
