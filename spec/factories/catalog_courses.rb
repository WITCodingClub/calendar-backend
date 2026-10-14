# frozen_string_literal: true

# == Schema Information
#
# Table name: catalog_courses
#
#  id                 :bigint           not null, primary key
#  corequisites       :jsonb            not null
#  course_number      :integer          not null
#  credit_hours       :integer
#  description        :text
#  details_fetched_at :datetime
#  prerequisites      :jsonb
#  restrictions       :jsonb            not null
#  subject_code       :string           not null
#  title              :string
#  typically_offered  :string           default([]), not null, is an Array
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  source_term_id     :bigint
#
# Indexes
#
#  index_catalog_courses_on_source_term_id                  (source_term_id)
#  index_catalog_courses_on_subject_code_and_course_number  (subject_code,course_number) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (source_term_id => terms.id)
#
FactoryBot.define do
  factory :catalog_course do
    subject_code { "COMP" }
    sequence(:course_number) { |n| 5000 + n }
    title { Faker::Educator.course_name }

    trait :with_details do
      description { Faker::Lorem.paragraph }
      credit_hours { 4 }
      typically_offered { %w[fall spring] }
      details_fetched_at { Time.current }
    end
  end
end
