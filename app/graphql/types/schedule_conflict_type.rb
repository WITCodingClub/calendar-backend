# frozen_string_literal: true

module Types
  class ScheduleConflictType < BaseObject
    description "Two sections that meet at the same time on the same day, during overlapping dates"

    field :crns, [ Integer ], null: false
    field :day, String, null: false
    field :times, [ String ], null: false, description: "The two meetings, as HH:MM-HH:MM"
  end
end
