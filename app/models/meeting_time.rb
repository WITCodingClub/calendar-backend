# == Schema Information
#
# Table name: meeting_times
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  begin_time            :integer
#  end_date              :datetime         not null
#  end_time              :integer
#  friday                :boolean
#  hours_week            :integer
#  meeting_schedule_type :integer
#  meeting_type          :integer
#  monday                :boolean
#  saturday              :boolean
#  start_date            :datetime         not null
#  sunday                :boolean
#  thursday              :boolean
#  tuesday               :boolean
#  wednesday             :boolean
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  academic_class_id     :bigint           not null
#  room_id               :bigint           not null
#
# Indexes
#
#  index_meeting_times_on_academic_class_id  (academic_class_id)
#  index_meeting_times_on_room_id            (room_id)
#
# Foreign Keys
#
#  fk_rails_...  (academic_class_id => courses.id)
#  fk_rails_...  (room_id => rooms.id)
#
class MeetingTime < ApplicationRecord
  belongs_to :course
  belongs_to :room
  has_one :building, through: :room

  enum :meeting_schedule_type, {
    lecture: 1, # LEC
    laboratory: 2 # LAB
  }

  enum :meeting_type, {
    class_meeting: 1 # CLAS
  }

  def fmt_begin_time
    hours = begin_time / 100
    minutes = begin_time % 100
    format("%02d:%02d", hours, minutes)
  end

  def fmt_end_time
    hours = end_time / 100
    minutes = end_time % 100
    format("%02d:%02d", hours, minutes)
  end

end
