# frozen_string_literal: true

module Types
  class MeetingTimeType < BaseObject
    description "One weekly meeting of a section"

    field :day, DayOfWeekEnum, null: false, method: :day_of_week
    field :day_of_week, Integer, null: false,
          description: "0 (Sunday) through 6 (Saturday)"
    field :begin_time, String, null: false,
          description: "24-hour HH:MM", method: :fmt_begin_time_military
    field :end_time, String, null: false,
          description: "24-hour HH:MM", method: :fmt_end_time_military
    field :begin_time_12h, String, null: false, method: :fmt_begin_time
    field :end_time_12h, String, null: false, method: :fmt_end_time
    field :duration_minutes, Integer, null: false
    field :meeting_type, String, null: false, method: :meeting_schedule_type
    field :all_day, Boolean, null: false, method: :all_day?
    field :location, LocationType, null: true,
          description: "Null when the section has no room assigned, as with online sections"

    def location
      building = object.building
      return nil if building.nil?

      { display: object.building_room, building: building, rooms: object.rooms }
    end

    def day_of_week
      Course::MeetingTime.day_of_weeks[object.day_of_week]
    end

    def duration_minutes
      ::Catalog::MeetingTimeSerializer.minutes_since_midnight(object.end_time) -
        ::Catalog::MeetingTimeSerializer.minutes_since_midnight(object.begin_time)
    end
  end
end
