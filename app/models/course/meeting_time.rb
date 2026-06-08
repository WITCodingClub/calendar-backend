# frozen_string_literal: true

class Course::MeetingTime < ApplicationRecord
  include MeetingTimeChangeTrackable
  include EncodedIds::HashidIdentifiable

  self.table_name = "course_meeting_times"

  set_public_id_prefix :mtt, min_hash_length: 12

  belongs_to :course
  belongs_to :room
  has_one :building, through: :room
  has_many :google_calendar_events, dependent: :destroy
  has_one :event_preference, as: :preferenceable, dependent: :destroy

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

  def building_room
    return nil unless room&.building

    b = room.building
    return nil if b.abbreviation.blank? || b.name.blank? ||
                  b.abbreviation == "TBD" || b.name == "To Be Determined"

    if room.number.to_i.zero? || room.number.to_s.upcase == "TBD"
      b.abbreviation
    else
      "#{b.abbreviation} #{room.formatted_number}"
    end
  end

  private

  def format_12_hour(hours, minutes)
    meridian = hours >= 12 ? "PM" : "AM"
    display_hour = hours == 0 ? 12 : (hours > 12 ? hours - 12 : hours)
    format("%d:%02d %s", display_hour, minutes, meridian)
  end
end
