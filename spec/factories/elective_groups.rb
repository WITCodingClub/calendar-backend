# frozen_string_literal: true

# == Schema Information
#
# Table name: elective_groups
#
#  id                 :bigint           not null, primary key
#  any_course         :boolean          default(FALSE), not null
#  heading            :text
#  min_courses        :integer
#  min_credits        :integer
#  name               :string           not null
#  notes              :text
#  position           :integer          default(0), not null
#  subject_codes      :string           default([]), not null, is an Array
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  program_plan_id    :bigint
#  requirement_set_id :bigint           not null
#
# Indexes
#
#  idx_elective_groups_unique                (requirement_set_id,program_plan_id,position) UNIQUE NULLS NOT DISTINCT
#  index_elective_groups_on_program_plan_id  (program_plan_id)
#
# Foreign Keys
#
#  fk_rails_...  (program_plan_id => program_plans.id) ON DELETE => cascade
#  fk_rails_...  (requirement_set_id => requirement_sets.id) ON DELETE => cascade
#
FactoryBot.define do
  factory :elective_group do
    requirement_set
    name { "#{Faker::Educator.subject} Electives" }
    heading { "#{name}, select two (2) courses from the following list:" }
    min_courses { 2 }
    sequence(:position)

    # A shared list from DegreeRequirements::SharedElectives.
    trait :subjects do
      name { "HSS Electives" }
      heading { "Humanities or social science elective" }
      min_courses { nil }
      subject_codes { %w[HIST PSYC] }
    end

    trait :any_course do
      name { "Free Electives" }
      heading { "Free or general elective" }
      min_courses { nil }
      any_course { true }
    end

    trait :for_plan do
      program_plan { association :program_plan, requirement_set: requirement_set }
    end
  end
end
