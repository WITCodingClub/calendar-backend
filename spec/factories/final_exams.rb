# frozen_string_literal: true

# == Schema Information
#
# Table name: final_exams
# Database name: primary
#
#  id            :bigint           not null, primary key
#  combined_crns :text
#  crn           :integer
#  end_time      :integer          not null
#  exam_date     :date             not null
#  location      :string
#  notes         :text
#  start_time    :integer          not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  course_id     :bigint
#  term_id       :bigint           not null
#
# Indexes
#
#  index_final_exams_on_course_id        (course_id)
#  index_final_exams_on_crn_and_term_id  (crn,term_id) UNIQUE
#  index_final_exams_on_term_id          (term_id)
#
# Foreign Keys
#
#  fk_rails_...  (course_id => courses.id)
#  fk_rails_...  (term_id => terms.id)
#
FactoryBot.define do
  factory :final_exam do
    course
    term { course&.term || association(:term) }
    crn { course&.crn || sequence(:crn) { |n| 10000 + n } }
    exam_date { course&.end_date || 1.month.from_now.to_date }
    start_time { 800 }
    end_time { 1000 }
    location { "WENTW 010" }
    notes { nil }
    combined_crns { nil }

    trait :afternoon do
      start_time { 1300 }
      end_time { 1500 }
    end

    trait :evening do
      start_time { 1800 }
      end_time { 2000 }
    end

    trait :with_combined_crns do
      combined_crns { [12345, 12346, 12347] }
    end

    # Orphan exam without a course (awaiting course import)
    trait :orphan do
      course { nil }
      sequence(:crn) { |n| 90000 + n }
      term
      exam_date { term.end_date || 1.week.from_now.to_date }
    end
  end
end
