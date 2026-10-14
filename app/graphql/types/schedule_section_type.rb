# frozen_string_literal: true

module Types
  class ScheduleSectionType < BaseObject
    description "A section in a schedule check"

    field :crn, Integer, null: false
    field :course_code, String, null: false, description: "e.g. \"COMP 2350-3B\""
    field :title, String, null: false
    field :schedule_type, String, null: false
    field :credit_hours, Integer, null: true
    field :meeting_times, [ ScheduleMeetingType ], null: false
  end
end
