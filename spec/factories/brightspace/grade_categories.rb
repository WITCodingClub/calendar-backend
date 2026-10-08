# frozen_string_literal: true

# == Schema Information
#
# Table name: brightspace_grade_categories
#
#  id                 :bigint           not null, primary key
#  drop_highest       :integer
#  drop_lowest        :integer
#  extra_credit       :boolean
#  name               :string           not null
#  removed_at         :datetime
#  weight             :decimal(8, 4)
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  course_offering_id :bigint           not null
#  source_id          :string           not null
#
# Indexes
#
#  index_brightspace_grade_categories_on_course_offering_id  (course_offering_id)
#  index_brightspace_grade_categories_on_source              (course_offering_id,source_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (course_offering_id => brightspace_course_offerings.id)
#
FactoryBot.define do
  factory :brightspace_grade_category, class: "Brightspace::GradeCategory" do
    association :course_offering, factory: :brightspace_course_offering
    sequence(:source_id) { |n| (80_000 + n).to_s }
    name { Faker::Lorem.word.capitalize }
  end
end
