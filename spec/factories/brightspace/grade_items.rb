# frozen_string_literal: true

# == Schema Information
#
# Table name: brightspace_grade_items
#
#  id                 :bigint           not null, primary key
#  extra_credit       :boolean
#  feedback           :text
#  graded_at          :datetime
#  grading_status     :string           not null
#  name               :string           not null
#  points_earned      :decimal(10, 4)
#  points_possible    :decimal(10, 4)
#  removed_at         :datetime
#  weight             :decimal(8, 4)
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  assignment_id      :bigint
#  course_offering_id :bigint           not null
#  grade_category_id  :bigint
#  source_id          :string           not null
#
# Indexes
#
#  index_brightspace_grade_items_on_assignment_id       (assignment_id)
#  index_brightspace_grade_items_on_course_offering_id  (course_offering_id)
#  index_brightspace_grade_items_on_grade_category_id   (grade_category_id)
#  index_brightspace_grade_items_on_source              (course_offering_id,source_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (assignment_id => brightspace_assignments.id)
#  fk_rails_...  (course_offering_id => brightspace_course_offerings.id)
#  fk_rails_...  (grade_category_id => brightspace_grade_categories.id)
#
FactoryBot.define do
  factory :brightspace_grade_item, class: "Brightspace::GradeItem" do
    association :course_offering, factory: :brightspace_course_offering
    sequence(:source_id) { |n| (81_000 + n).to_s }
    name { Faker::Lorem.word.capitalize }
    grading_status { "ungraded" }
    points_possible { 10 }

    trait :graded do
      grading_status { "graded" }
      points_earned { 8 }
    end
  end
end
