# == Schema Information
#
# Table name: courses
# Database name: primary
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
class Course < ApplicationRecord
  include CourseChangeTrackable

  belongs_to :term

  has_and_belongs_to_many :faculties
  has_many :meeting_times, dependent: :destroy
  has_many :rooms, through: :meeting_times
  has_many :enrollments, dependent: :destroy
  has_many :users, through: :enrollments

  validates :crn, uniqueness: true, allow_nil: true

  enum :schedule_type, {
    hybrid: "HYB",
    laboratory: "LAB",
    lecture: "LEC",
    online_sync_lab: "OLB",
    online_sync_lecture: "OLC",
    rotating_lab: "RLB",
    rotating_lecture: "RLC"
  }

end
