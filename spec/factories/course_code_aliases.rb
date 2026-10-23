# frozen_string_literal: true

# == Schema Information
#
# Table name: course_code_aliases
#
#  id                 :bigint           not null, primary key
#  from_course_number :integer          not null
#  from_subject_code  :string           not null
#  note               :string
#  reviewed_at        :datetime
#  source             :string           not null
#  to_course_number   :integer          not null
#  to_subject_code    :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
# Indexes
#
#  idx_course_code_aliases_unique                      (from_subject_code,from_course_number,to_subject_code,to_course_number) UNIQUE
#  idx_on_to_subject_code_to_course_number_49e737555f  (to_subject_code,to_course_number)
#
FactoryBot.define do
  factory :course_code_alias do
    from_subject_code { "COMP" }
    sequence(:from_course_number) { |n| 100 + n }
    to_subject_code { "COMP" }
    sequence(:to_course_number) { |n| 5000 + n }
    source { "title_match" }

    trait :reviewed do
      reviewed_at { Time.current }
    end
  end
end
