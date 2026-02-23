# frozen_string_literal: true

# == Schema Information
#
# Table name: degree_programs
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  active                :boolean          default(TRUE), not null
#  catalog_year          :integer          not null
#  college               :string
#  credit_hours_required :decimal(5, 2)
#  degree_type           :string           not null
#  department            :string
#  leopardweb_code       :string           not null
#  level                 :string           not null
#  minimum_gpa           :decimal(3, 2)
#  program_code          :string           not null
#  program_name          :string           not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#
# Indexes
#
#  index_degree_programs_on_active                         (active)
#  index_degree_programs_on_catalog_year_and_program_code  (catalog_year,program_code)
#  index_degree_programs_on_leopardweb_code                (leopardweb_code) UNIQUE
#  index_degree_programs_on_program_code                   (program_code) UNIQUE
#
require "rails_helper"

RSpec.describe DegreeProgram do
  describe "validations" do
    subject { build(:degree_program) }

    it { is_expected.to validate_presence_of(:program_code) }
    it { is_expected.to validate_presence_of(:leopardweb_code) }
    it { is_expected.to validate_presence_of(:program_name) }
    it { is_expected.to validate_presence_of(:degree_type) }
    it { is_expected.to validate_presence_of(:level) }
    it { is_expected.to validate_presence_of(:catalog_year) }

    it { is_expected.to validate_uniqueness_of(:program_code) }
    it { is_expected.to validate_uniqueness_of(:leopardweb_code) }

    it { is_expected.to validate_numericality_of(:catalog_year).only_integer.is_greater_than(2000) }
    it { is_expected.to validate_numericality_of(:credit_hours_required).is_greater_than(0).allow_nil }
    it { is_expected.to validate_numericality_of(:minimum_gpa).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(4.0).allow_nil }
  end

  describe "associations" do
    it { is_expected.to have_many(:user_degree_programs).dependent(:destroy) }
    it { is_expected.to have_many(:users).through(:user_degree_programs) }
    it { is_expected.to have_many(:degree_requirements).dependent(:destroy) }
    it { is_expected.to have_many(:degree_evaluation_snapshots).dependent(:destroy) }
  end

  describe "scopes" do
    let!(:active_program) { create(:degree_program, active: true) }
    let!(:inactive_program) { create(:degree_program, :inactive) }

    describe ".active" do
      it "returns only active programs" do
        expect(described_class.active).to include(active_program)
        expect(described_class.active).not_to include(inactive_program)
      end
    end

    describe ".by_catalog_year" do
      let!(:program_2026) { create(:degree_program, catalog_year: 2026) }
      let!(:program_2025) { create(:degree_program, catalog_year: 2025) }

      it "returns programs for the specified catalog year" do
        expect(described_class.by_catalog_year(2026)).to include(program_2026)
        expect(described_class.by_catalog_year(2026)).not_to include(program_2025)
      end
    end

    describe ".by_level" do
      let!(:undergrad) { create(:degree_program, level: "Undergraduate") }
      let!(:graduate) { create(:degree_program, :graduate) }

      it "returns programs for the specified level" do
        expect(described_class.by_level("Graduate")).to include(graduate)
        expect(described_class.by_level("Graduate")).not_to include(undergrad)
      end
    end
  end
end
