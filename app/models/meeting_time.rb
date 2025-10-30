# == Schema Information
#
# Table name: meeting_times
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  begin_time            :integer          not null
#  end_date              :datetime         not null
#  end_time              :integer          not null
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
#  course_id             :bigint           not null
#  room_id               :bigint           not null
#
# Indexes
#
#  index_meeting_times_on_course_id  (course_id)
#  index_meeting_times_on_room_id    (room_id)
#
# Foreign Keys
#
#  fk_rails_...  (course_id => courses.id)
#  fk_rails_...  (room_id => rooms.id)
#
class MeetingTime < ApplicationRecord
  belongs_to :course
  belongs_to :room
  has_one :building, through: :room

  def event_color
    case meeting_schedule_type
    when "lecture"
      ColorPalette::MAP[:gold]
    when "laboratory"
      ColorPalette::MAP[:ruby_red]
    else
      ColorPalette::MAP[:platinum]
    end
  end

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
