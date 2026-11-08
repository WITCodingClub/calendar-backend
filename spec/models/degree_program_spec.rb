# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: degree_programs
#
#  id                :bigint           not null, primary key
#  kind              :string           not null
#  level             :string           not null
#  name              :string           not null
#  slug              :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  parent_program_id :bigint
#
# Indexes
#
#  index_degree_programs_on_parent_program_id  (parent_program_id)
#  index_degree_programs_on_slug               (slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (parent_program_id => degree_programs.id) ON DELETE => nullify
#
RSpec.describe DegreeProgram do
  subject { create(:degree_program) }

  it { is_expected.to belong_to(:parent_program).class_name("DegreeProgram").optional }
  it { is_expected.to have_many(:concentrations).class_name("DegreeProgram").with_foreign_key(:parent_program_id).dependent(:nullify) }
  it { is_expected.to have_many(:requirement_sets).dependent(:destroy) }
  it { is_expected.to have_many(:catalog_years).through(:requirement_sets) }
  it { is_expected.to have_many(:program_pathway_steps).dependent(:restrict_with_error) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:slug) }
  it { is_expected.to validate_uniqueness_of(:slug) }
  it { is_expected.to allow_value("computer-science-bs").for(:slug) }
  it { is_expected.not_to allow_values("Computer Science", "cs_bs", "-cs", "cs-").for(:slug) }

  it do
    expect(subject).to define_enum_for(:kind).with_values(DegreeProgram::KINDS).backed_by_column_of_type(:string).validating
  end

  it do
    expect(subject).to define_enum_for(:level).with_values(DegreeProgram::LEVELS).backed_by_column_of_type(:string).validating
  end

  it "lists the concentrations of a major" do
    concentration = create(:degree_program, :concentration, parent_program: subject)

    expect(subject.concentrations).to eq([ concentration ])
  end

  # A cross-record check, so no matcher covers it.
  it "takes as parent only a program with no parent of its own" do
    concentration = create(:degree_program, :concentration, parent_program: subject)

    expect(build(:degree_program, :concentration, parent_program: concentration)).not_to be_valid
    subject.parent_program = subject
    expect(subject).not_to be_valid
    expect(subject.errors[:parent_program]).to be_present
  end

  it "maps an old catalog slug of a renamed program to its new slug" do
    expect(described_class.current_slug("biological-engineering-program")).to eq("biological-engineering-bs")
    expect(described_class.current_slug("computer-science-bs")).to eq("computer-science-bs")
  end

  it "makes a valid slug from a catalog path with an underscore or capitals" do
    slug = described_class.slug_for_path("/management/construction-management/Construction-Management-BS-realest_facmgmt/")

    expect(slug).to eq("construction-management-bs-realest-facmgmt")
    expect(build(:degree_program, slug: slug)).to be_valid
    expect(described_class.slug_for_path("/")).to be_nil
  end

  # Every renamed slug points at a slug the model accepts, or the import of
  # that program fails validation.
  it "maps each renamed slug to a valid slug" do
    described_class::RENAMED_SLUGS.each_value do |slug|
      expect(build(:degree_program, slug: slug)).to be_valid, slug
    end
  end

  it "finds its requirement set for a catalog year" do
    catalog_year = create(:catalog_year)
    requirement_set = create(:requirement_set, degree_program: subject, catalog_year: catalog_year)
    create(:requirement_set, degree_program: subject)

    expect(subject.requirement_set_for(catalog_year)).to eq(requirement_set)
  end
end
