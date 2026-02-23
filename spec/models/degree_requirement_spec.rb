# frozen_string_literal: true

# == Schema Information
#
# Table name: degree_requirements
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  area_name             :string           not null
#  course_choice_logic   :string
#  course_number         :integer
#  courses_required      :integer
#  credits_required      :decimal(5, 2)
#  requirement_name      :string           not null
#  requirement_type      :string           not null
#  rule_text             :text
#  subject               :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  degree_program_id     :bigint           not null
#  parent_requirement_id :bigint
#
# Indexes
#
#  index_degree_requirements_on_degree_program_id                (degree_program_id)
#  index_degree_requirements_on_degree_program_id_and_area_name  (degree_program_id,area_name)
#  index_degree_requirements_on_parent_requirement_id            (parent_requirement_id)
#  index_degree_requirements_on_requirement_type                 (requirement_type)
#
# Foreign Keys
#
#  fk_rails_...  (degree_program_id => degree_programs.id)
#  fk_rails_...  (parent_requirement_id => degree_requirements.id)
#
require "rails_helper"

RSpec.describe DegreeRequirement do
  describe "validations" do
    it { is_expected.to validate_presence_of(:area_name) }
    it { is_expected.to validate_presence_of(:requirement_name) }
    it { is_expected.to validate_presence_of(:requirement_type) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:degree_program) }
    it { is_expected.to belong_to(:parent_requirement).class_name("DegreeRequirement").optional }
    it { is_expected.to have_many(:child_requirements).class_name("DegreeRequirement").with_foreign_key("parent_requirement_id").dependent(:destroy) }
    it { is_expected.to have_many(:requirement_completions).dependent(:destroy) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:requirement_type).backed_by_column_of_type(:string).with_values(core: "core", major: "major", minor: "minor", elective: "elective", general_education: "general_education", concentration: "concentration") }
  end

  describe "scopes" do
    let(:program) { create(:degree_program) }
    let!(:core_requirement) { create(:degree_requirement, degree_program: program, area_name: "Core", requirement_type: :core) }
    let!(:elective_requirement) { create(:degree_requirement, :elective, degree_program: program, area_name: "Electives") }
    let!(:parent_requirement) { create(:degree_requirement, degree_program: program) }
    let!(:child_requirement) { create(:degree_requirement, degree_program: program, parent_requirement: parent_requirement) }

    describe ".by_area" do
      it "returns requirements for the specified area" do
        expect(described_class.by_area("Core")).to include(core_requirement)
        expect(described_class.by_area("Core")).not_to include(elective_requirement)
      end
    end

    describe ".by_type" do
      it "returns requirements of the specified type" do
        expect(described_class.by_type(:elective)).to include(elective_requirement)
        expect(described_class.by_type(:elective)).not_to include(core_requirement)
      end
    end

    describe ".root_requirements" do
      it "returns only requirements without a parent" do
        expect(described_class.root_requirements).to include(core_requirement, elective_requirement, parent_requirement)
        expect(described_class.root_requirements).not_to include(child_requirement)
      end
    end

    describe ".child_requirements_of" do
      it "returns child requirements of the specified parent" do
        expect(described_class.child_requirements_of(parent_requirement)).to include(child_requirement)
        expect(described_class.child_requirements_of(parent_requirement)).not_to include(core_requirement)
      end
    end
  end

  describe "#specific_course?" do
    it "returns true when both subject and course_number are present" do
      requirement = create(:degree_requirement, :specific_course)
      expect(requirement.specific_course?).to be true
    end

    it "returns false when subject is missing" do
      requirement = create(:degree_requirement, subject: nil, course_number: 1000)
      expect(requirement.specific_course?).to be false
    end

    it "returns false when course_number is missing" do
      requirement = create(:degree_requirement, subject: "COMP", course_number: nil)
      expect(requirement.specific_course?).to be false
    end
  end

  describe "#course_identifier" do
    it "returns formatted course identifier when specific course" do
      requirement = create(:degree_requirement, :specific_course, subject: "COMP", course_number: 1000)
      expect(requirement.course_identifier).to eq("COMP 1000")
    end

    it "returns nil when not a specific course" do
      requirement = create(:degree_requirement, subject: nil, course_number: nil)
      expect(requirement.course_identifier).to be_nil
    end
  end
end
