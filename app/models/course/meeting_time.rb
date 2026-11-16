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
  include CourseChangeTrackable
  include EncodedIds::HashidIdentifiable

  tracks_calendar_changes "begin_time", "end_time", "day_of_week", "start_date", "end_date", course_id: :course_id

  self.table_name = "course_meeting_times"

  set_public_id_prefix :mtt, min_hash_length: 12

  # WIT stores an async or all-day section as 12:01pm to 11:59pm.
  ALL_DAY_BEGIN = 1201
  ALL_DAY_END   = 2359

  # The location text of a calendar event that has no real room.
  TBD_LOCATION = "TBD"

  belongs_to :course
  has_many :meeting_time_rooms, class_name: "Course::MeetingTimeRoom",
                                foreign_key: :meeting_time_id, dependent: :destroy, inverse_of: :meeting_time
  has_many :rooms, through: :meeting_time_rooms
  # Nullify, never destroy: the tracking row is the only pointer to the real
  # event in Google Calendar. Cleanup::OrphanedCalendarEventsJob deletes orphans
  # from Google before removing the row.
  has_many :calendar_events, dependent: :nullify
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

  def all_day?
    begin_time == ALL_DAY_BEGIN && end_time == ALL_DAY_END
  end

  def event_color
    case meeting_schedule_type
    when "lecture"    then Preferences::Colors::BANANA
    when "laboratory" then Preferences::Colors::TOMATO
    else                   Preferences::Colors::GRAPHITE
    end
  end

  # No room, or only placeholder rooms or a placeholder building. Of meeting
  # times with the same day and hours, Course#filtered_meeting_times keeps one
  # that is not TBD.
  def tbd_location?
    rooms.empty? || building.tbd? || rooms.all?(&:tbd?)
  end

  # The location of a calendar event: "Wentworth Hall - 212 / 214", only the
  # rooms when the building is a placeholder, "TBD", or nil with no room.
  def location_text
    real_rooms = rooms.reject(&:tbd?)
    if real_rooms.any? && building && !building.tbd?
      "#{building.name} - #{room_list(real_rooms)}"
    elsif real_rooms.any?
      room_list(real_rooms)
    elsif building&.tbd? || room&.tbd?
      TBD_LOCATION
    end
  end

  # The short location of a listing: "WENTW 212 / 214", the abbreviation with
  # no real room, or nil for a placeholder building.
  def building_room
    return nil if building.nil? || building.tbd?

    real_rooms = rooms.reject(&:tbd?)
    real_rooms.empty? ? building.abbreviation : "#{building.abbreviation} #{room_list(real_rooms)}"
  end

  private

  def room_list(rooms) = rooms.map(&:formatted_number).join(Room::LIST_SEPARATOR)

  def format_12_hour(hours, minutes)
    meridian = hours >= 12 ? "PM" : "AM"
    display_hour = hours == 0 ? 12 : (hours > 12 ? hours - 12 : hours)
    format("%d:%02d %s", display_hour, minutes, meridian)
  end
end
