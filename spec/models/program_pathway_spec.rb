# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: program_pathways
#
#  id                 :bigint           not null, primary key
#  active             :boolean          default(TRUE), not null
#  kind               :string           not null
#  max_shared_courses :integer
#  max_shared_credits :integer
#  name               :string           not null
#  slug               :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
# Indexes
#
#  index_program_pathways_on_slug  (slug) UNIQUE
#
RSpec.describe ProgramPathway do
  subject { create(:program_pathway) }

  it { is_expected.to have_many(:steps).class_name("ProgramPathwayStep").dependent(:delete_all) }
  it { is_expected.to have_many(:degree_programs).through(:steps) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:slug) }
  it { is_expected.to validate_uniqueness_of(:slug) }
  it { is_expected.to validate_numericality_of(:max_shared_courses).only_integer.is_greater_than_or_equal_to(0).allow_nil }
  it { is_expected.to validate_numericality_of(:max_shared_credits).only_integer.is_greater_than_or_equal_to(0).allow_nil }

  it do
    expect(subject).to define_enum_for(:kind)
      .with_values(three_plus_one: "three_plus_one", four_plus_one: "four_plus_one", five_year: "five_year")
      .backed_by_column_of_type(:string).validating
  end

  it "lists its programs in order" do
    master = create(:degree_program, :master)
    bachelor = create(:degree_program)
    create(:program_pathway_step, program_pathway: subject, degree_program: master, position: 2)
    create(:program_pathway_step, program_pathway: subject, degree_program: bachelor, position: 1, plan_years: 3)

    expect(subject.steps.map(&:degree_program)).to eq([ bachelor, master ])
  end

  it "lists only the active pathways" do
    create(:program_pathway, active: false)

    expect(described_class.active).to eq([ subject ])
  end
end
