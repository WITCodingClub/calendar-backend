# frozen_string_literal: true

# == Schema Information
#
# Table name: elective_groups
#
#  id                 :bigint           not null, primary key
#  heading            :text
#  min_courses        :integer
#  min_credits        :integer
#  name               :string           not null
#  notes              :text
#  position           :integer          default(0), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  program_plan_id    :bigint
#  requirement_set_id :bigint           not null
#
# Indexes
#
#  index_elective_groups_on_program_plan_id     (program_plan_id)
#  index_elective_groups_on_requirement_set_id  (requirement_set_id)
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

    trait :for_plan do
      program_plan { association :program_plan, requirement_set: requirement_set }
    end
  end
end
