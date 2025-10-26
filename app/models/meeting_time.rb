class MeetingTime < ApplicationRecord
  belongs_to :academic_class
  belongs_to :room
  has_one :building, through: :room

  enum :meeting_schedule_type, {
    lecture: 1, # LEC
    laboratory: 2 # LAB
  }

  enum :meeting_type, {
    class_meeting: 1 # CLAS
  }

end
