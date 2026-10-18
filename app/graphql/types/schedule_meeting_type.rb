# frozen_string_literal: true

module Types
  class ScheduleMeetingType < BaseObject
    description "One weekly meeting of a section in a schedule check"

    field :day, String, null: false, description: "e.g. \"monday\""
    field :begin_time, String, null: false, description: "HH:MM, 24-hour"
    field :end_time, String, null: false, description: "HH:MM, 24-hour"
  end
end
