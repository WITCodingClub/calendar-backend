# frozen_string_literal: true

require "rails_helper"

RSpec.describe StudentProgram, type: :model do
  it { is_expected.to belong_to(:user) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to define_enum_for(:role).with_values(described_class::ROLES).backed_by_column_of_type(:string).validating }
  it { is_expected.to define_enum_for(:status).with_values(described_class::STATUSES).backed_by_column_of_type(:string).validating }

  it do
    expect(subject).to define_enum_for(:source).with_values(described_class::SOURCES)
                                               .backed_by_column_of_type(:string).with_prefix.validating
  end

  it "names its catalog term and catalog year from the Banner code" do
    program = build(:student_program, catalog_term_uid: 202620)

    expect(program.catalog_term).to eq("Spring 2026")
    expect(program.catalog_year).to eq("2025-2026")
  end
end
