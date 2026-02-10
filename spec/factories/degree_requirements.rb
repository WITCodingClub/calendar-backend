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
FactoryBot.define do
  factory :degree_requirement do
    degree_program
    sequence(:area_name) { |n| "Area #{n}" }
    sequence(:requirement_name) { |n| "Requirement #{n}" }
    requirement_type { "core" }
    credits_required { 3.0 }
    courses_required { 1 }
    parent_requirement { nil }
    rule_text { "Complete the specified course" }
    subject { nil }
    course_number { nil }
    course_choice_logic { nil }

    trait :specific_course do
      subject { "COMP" }
      course_number { 1000 }
      rule_text { "Complete COMP1000" }
    end

    trait :elective do
      requirement_type { "elective" }
      credits_required { 12.0 }
      courses_required { 4 }
      course_choice_logic { "any" }
    end

    trait :major_requirement do
      requirement_type { "major" }
      area_name { "Major Core" }
    end

    trait :with_children do
      after(:create) do |requirement|
        create_list(:degree_requirement, 2, degree_program: requirement.degree_program, parent_requirement: requirement)
      end
    end
  end
end
