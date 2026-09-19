# frozen_string_literal: true

# == Schema Information
#
# Table name: courses
#
#  id                :bigint           not null, primary key
#  course_number     :integer          not null
#  credit_hours      :integer
#  crn               :integer          not null
#  end_date          :date             not null
#  grade_mode        :string
#  is_section_linked :boolean          default(FALSE), not null
#  link_identifier   :string
#  schedule_type     :string           not null
#  seats_available   :integer
#  seats_capacity    :integer
#  section_number    :string           not null
#  start_date        :date             not null
#  status            :string           default("active"), not null
#  subject           :string           not null
#  title             :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  term_id           :bigint           not null
#
# Indexes
#
#  index_courses_on_course_and_link_identifier  (term_id,subject,course_number,link_identifier)
#  index_courses_on_crn_and_term_id             (crn,term_id) UNIQUE
#  index_courses_on_status                      (status)
#  index_courses_on_term_id                     (term_id)
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#
FactoryBot.define do
  factory :course do
    association :term
    sequence(:crn) { |n| 10_000 + n }
    subject { "COMP" }
    sequence(:course_number) { |n| 1000 + n }
    section_number { "01" }
    schedule_type { :lecture }
    title { Faker::Educator.course_name }
    start_date { Date.new(2026, 9, 8) }
    end_date { Date.new(2026, 12, 15) }
  end
end
