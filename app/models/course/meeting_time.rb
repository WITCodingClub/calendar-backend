# frozen_string_literal: true

# == Schema Information
#
# Table name: course_meeting_times
#
#  id                    :bigint           not null, primary key
#  begin_time            :integer          not null
#  day_of_week           :integer          not null
#  end_date              :datetime         not null
#  end_time              :integer          not null
#  hours_week            :integer
#  meeting_schedule_type :integer          not null
#  meeting_type          :integer          not null
#  start_date            :datetime         not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  course_id             :bigint           not null
#
# Indexes
#
#  index_course_meeting_times_on_course_id    (course_id)
#  index_course_meeting_times_on_day_of_week  (day_of_week)
#
# Foreign Keys
#
#  fk_rails_...  (course_id => courses.id)
#
class Course::MeetingTime < ApplicationRecord
  include MeetingTimeChangeTrackable
  include EncodedIds::HashidIdentifiable

  self.table_name = "course_meeting_times"

  set_public_id_prefix :mtt, min_hash_length: 12

  belongs_to :course
  has_many :meeting_time_rooms, class_name: "Course::MeetingTimeRoom",
                                foreign_key: :meeting_time_id, dependent: :destroy, inverse_of: :meeting_time
  has_many :rooms, through: :meeting_time_rooms
  has_many :google_calendar_events, dependent: :destroy
  has_one :event_preference, as: :preferenceable, dependent: :destroy

  def room
    rooms.first
  end

  def building
    room&.building
  end

  enum :meeting_schedule_type, { lecture: 1, laboratory: 2 }
  enum :meeting_type,          { class_meeting: 1 }
  enum :day_of_week,           { sunday: 0, monday: 1, tuesday: 2, wednesday: 3,
                                 thursday: 4, friday: 5, saturday: 6 }

  def fmt_begin_time
    format_12_hour(begin_time / 100, begin_time % 100)
  end

  def fmt_end_time
    format_12_hour(end_time / 100, end_time % 100)
  end

  def fmt_begin_time_military
    format("%02d:%02d", begin_time / 100, begin_time % 100)
  end

  def fmt_end_time_military
    format("%02d:%02d", end_time / 100, end_time % 100)
  end

  def formatted_time_range
    "#{fmt_begin_time} - #{fmt_end_time}"
  end

  # Events spanning 12:01pm-11:59pm are considered "all day" by the university
  def all_day?
    begin_time == 1201 && end_time == 2359
  end

  def event_color
    case meeting_schedule_type
    when "lecture"    then GoogleColors::EVENT_MAP[5]
    when "laboratory" then GoogleColors::EVENT_MAP[11]
    else                   GoogleColors::EVENT_MAP[8]
    end
  end

  def building_room
    b = building
    return nil unless b
    return nil if b.abbreviation.blank? || b.name.blank? ||
                  b.abbreviation == "TBD" || b.name == "To Be Determined"

    valid_rooms = rooms.reject { |r| r.number.to_i.zero? || r.number.to_s.upcase == "TBD" }
    if valid_rooms.empty?
      b.abbreviation
    else
      "#{b.abbreviation} #{valid_rooms.map(&:formatted_number).join(' / ')}"
    end
  end

  private

  def format_12_hour(hours, minutes)
    meridian = hours >= 12 ? "PM" : "AM"
    display_hour = hours == 0 ? 12 : (hours > 12 ? hours - 12 : hours)
    format("%d:%02d %s", display_hour, minutes, meridian)
  end
end
