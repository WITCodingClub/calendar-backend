# frozen_string_literal: true

# == Schema Information
#
# Table name: courses
#
#  id             :bigint           not null, primary key
#  course_number  :integer
#  credit_hours   :integer
#  crn            :integer
#  end_date       :date
#  grade_mode     :string
#  schedule_type  :string           not null
#  section_number :string           not null
#  start_date     :date
#  subject        :string
#  title          :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  term_id        :bigint           not null
#
# Indexes
#
#  index_courses_on_crn      (crn) UNIQUE
#  index_courses_on_term_id  (term_id)
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#
FactoryBot.define do
  factory :course do
    term
    sequence(:crn) { |n| 10000 + n }
    subject { "CS" }
    course_number { 101 }
    section_number { "01" }
    title { "Introduction to Computer Science" }
    schedule_type { :lecture }
    credit_hours { 3 }
    grade_mode { "Standard Letter" }
    start_date { 3.days.from_now }
    end_date { 3.months.from_now }
  end
end
