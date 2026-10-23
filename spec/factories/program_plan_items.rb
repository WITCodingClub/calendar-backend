# frozen_string_literal: true

# == Schema Information
#
# Table name: program_plan_items
#
#  id                :bigint           not null, primary key
#  course_number     :integer
#  footnote          :string
#  kind              :string           not null
#  lab_hours         :integer
#  label             :string
#  lecture_hours     :integer
#  max_credits       :integer
#  min_credits       :integer
#  options           :jsonb            not null
#  position          :integer          not null
#  season            :string           not null
#  subject_code      :string
#  year_index        :integer          not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  catalog_course_id :bigint
#  elective_group_id :bigint
#  program_plan_id   :bigint           not null
#
# Indexes
#
#  index_program_plan_items_on_catalog_course_id               (catalog_course_id)
#  index_program_plan_items_on_elective_group_id               (elective_group_id)
#  index_program_plan_items_on_program_plan_id_and_position    (program_plan_id,position) UNIQUE
#  index_program_plan_items_on_subject_code_and_course_number  (subject_code,course_number)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_course_id => catalog_courses.id) ON DELETE => nullify
#  fk_rails_...  (elective_group_id => elective_groups.id) ON DELETE => nullify
#  fk_rails_...  (program_plan_id => program_plans.id) ON DELETE => cascade
#
FactoryBot.define do
  factory :program_plan_item do
    program_plan
    year_index { 1 }
    season { "fall" }
    sequence(:position)
    kind { "course" }
    subject_code { "COMP" }
    sequence(:course_number) { |n| 5000 + n }
    label { Faker::Educator.course_name }
    min_credits { 4 }
    max_credits { 4 }

    trait :placeholder do
      kind { "placeholder" }
      subject_code { nil }
      course_number { nil }
      label { "Computer Science Elective" }
    end

    trait :choice do
      kind { "choice" }
      subject_code { nil }
      course_number { nil }
      options do
        [ { "subject_code" => "COMP", "course_number" => 1000 },
          { "subject_code" => "COMP", "course_number" => 1099 } ]
      end
    end
  end
end
