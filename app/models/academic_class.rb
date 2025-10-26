class AcademicClass < ApplicationRecord
  belongs_to :term

  has_and_belongs_to_many :faculties
  has_many :meeting_times, dependent: :destroy
  has_many :rooms, through: :meeting_times

  enum :schedule_type, {
    lecture: 1, # LEC
    laboratory: 2 # LAB
  }

end
