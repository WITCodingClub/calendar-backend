# frozen_string_literal: true

# == Schema Information
#
# Table name: meeting_times
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  begin_time            :integer          not null
#  day_of_week           :integer
#  end_date              :datetime         not null
#  end_time              :integer          not null
#  hours_week            :integer
#  meeting_schedule_type :integer
#  meeting_type          :integer
#  start_date            :datetime         not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  course_id             :bigint           not null
#  room_id               :bigint           not null
#
# Indexes
#
#  index_meeting_times_on_course_id    (course_id)
#  index_meeting_times_on_day_of_week  (day_of_week)
#  index_meeting_times_on_room_id      (room_id)
#
# Foreign Keys
#
#  fk_rails_...  (course_id => courses.id)
#  fk_rails_...  (room_id => rooms.id)
#
class MeetingTime < ApplicationRecord
  include MeetingTimeChangeTrackable
  include PublicIdentifiable

  set_public_id_prefix :mtt, min_hash_length: 12

  belongs_to :course
  belongs_to :room
  has_one :building, through: :room
  has_many :google_calendar_events, dependent: :destroy
  has_one :event_preference, as: :preferenceable, dependent: :destroy

  def event_color
    case meeting_schedule_type
    when "lecture"
      GoogleColors::EVENT_MAP[5]
      # ColorPalette::MAP[:gold]
    when "laboratory"
      # ColorPalette::MAP[:ruby_red]
      GoogleColors::EVENT_MAP[11]
    else
      # ColorPalette::MAP[:platinum]
      GoogleColors::EVENT_MAP[8]
    end
  end

  # Day of week enum (matches Ruby's Date.wday: 0=Sunday, 1=Monday, ..., 6=Saturday)
  enum :day_of_week, {
    sunday: 0,
    monday: 1,
    tuesday: 2,
    wednesday: 3,
    thursday: 4,
    friday: 5,
    saturday: 6
  }

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
    format_12_hour(hours, minutes)
  end

  def fmt_end_time
    hours = end_time / 100
    minutes = end_time % 100
    format_12_hour(hours, minutes)
  end

  def fmt_begin_time_military
    hours = begin_time / 100
    minutes = begin_time % 100
    format_24_hour(hours, minutes)
  end

  def fmt_end_time_military
    hours = end_time / 100
    minutes = end_time % 100
    format_24_hour(hours, minutes)
  end

  def formatted_time_range
    "#{fmt_begin_time} - #{fmt_end_time}"
  end

  def building_room
    return nil unless room&.building

    # Don't show TBD/empty locations
    # LeopardWeb sends null/empty for unassigned locations, not "TBD" placeholders
    if room.building.abbreviation.blank? ||
       room.building.name.blank? ||
       room.building.abbreviation == "TBD" ||
       room.building.name == "To Be Determined"
      return nil
    end

    # Format as "BUILDING ROOM" or just "BUILDING" if room is 0 or TBD
    if room.number == 0 || room.number.to_s.upcase == "TBD"
      room.building.abbreviation
    else
      "#{room.building.abbreviation} #{room.formatted_number}"
    end
  end

  private

  def format_12_hour(hours, minutes)
    meridian = hours >= 12 ? "PM" : "AM"
    display_hour = hours == 0 ? 12 : (hours > 12 ? hours - 12 : hours)
    format("%d:%02d %s", display_hour, minutes, meridian)
  end

  def format_24_hour(hours, minutes)
    format("%02d:%02d", hours, minutes)
  end

end
