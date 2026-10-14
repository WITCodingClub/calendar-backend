# frozen_string_literal: true

module Types
  class ScheduleTotalsType < BaseObject
    description "Totals for the week"

    field :credit_hours, Integer, null: false,
          description: "Banner's credits for linked sections (a lab is 0); a course without them counts once"
    field :days, [ String ], null: false
    field :earliest_start, String, null: true
    field :latest_end, String, null: true
    field :meetings_before_nine, Integer, null: false, description: "Weekly meetings that start before 9:00"
  end
end
