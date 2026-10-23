# frozen_string_literal: true

# == Schema Information
#
# Table name: catalog_year_courses
#
#  id                :bigint           not null, primary key
#  course_number     :integer          not null
#  description       :text
#  max_credits       :integer
#  min_credits       :integer
#  prerequisite_text :text
#  subject_code      :string           not null
#  title             :string
#  typically_offered :string           default([]), not null, is an Array
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  catalog_course_id :bigint
#  catalog_year_id   :bigint           not null
#
# Indexes
#
#  idx_catalog_year_courses_unique                               (catalog_year_id,subject_code,course_number) UNIQUE
#  index_catalog_year_courses_on_catalog_course_id               (catalog_course_id)
#  index_catalog_year_courses_on_subject_code_and_course_number  (subject_code,course_number)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_course_id => catalog_courses.id) ON DELETE => nullify
#  fk_rails_...  (catalog_year_id => catalog_years.id) ON DELETE => cascade
#
FactoryBot.define do
  factory :catalog_year_course do
    catalog_year
    subject_code { "COMP" }
    sequence(:course_number) { |n| 5000 + n }
    title { Faker::Educator.course_name.upcase }
    description { Faker::Lorem.paragraph }
    min_credits { 4 }
    max_credits { 4 }
    typically_offered { %w[fall spring] }
  end
end
