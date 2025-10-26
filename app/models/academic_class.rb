class AcademicClass < ApplicationRecord
  belongs_to :term

  has_and_belongs_to_many :faculties
  has_many :meeting_times, dependent: :destroy
  has_many :rooms, through: :meeting_times

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
