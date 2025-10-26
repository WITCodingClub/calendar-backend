# == Schema Information
#
# Table name: academic_classes
#
#  id             :bigint           not null, primary key
#  course_number  :integer
#  credit_hours   :integer
#  crn            :integer
#  grade_mode     :string
#  schedule_type  :string           not null
#  section_number :string           not null
#  subject        :string
#  title          :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  term_id        :bigint           not null
#
# Indexes
#
#  index_academic_classes_on_crn      (crn) UNIQUE
#  index_academic_classes_on_term_id  (term_id)
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#
class AcademicClass < ApplicationRecord
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
