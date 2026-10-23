# frozen_string_literal: true

# == Schema Information
#
# Table name: elective_group_courses
#
#  id                :bigint           not null, primary key
#  course_number     :integer          not null
#  position          :integer          default(0), not null
#  requires_approval :boolean          default(FALSE), not null
#  subject_code      :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  catalog_course_id :bigint
#  elective_group_id :bigint           not null
#
# Indexes
#
#  idx_elective_group_courses_unique                               (elective_group_id,subject_code,course_number) UNIQUE
#  index_elective_group_courses_on_catalog_course_id               (catalog_course_id)
#  index_elective_group_courses_on_subject_code_and_course_number  (subject_code,course_number)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_course_id => catalog_courses.id) ON DELETE => nullify
#  fk_rails_...  (elective_group_id => elective_groups.id) ON DELETE => cascade
#
FactoryBot.define do
  factory :elective_group_course do
    elective_group
    subject_code { "COMP" }
    sequence(:course_number) { |n| 5000 + n }

    trait :requires_approval do
      requires_approval { true }
    end
  end
end
