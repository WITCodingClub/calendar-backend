# frozen_string_literal: true

module Types
  class FinalExamType < BaseObject
    description "The scheduled final exam for a section"

    field :date, GraphQL::Types::ISO8601Date, null: false, method: :exam_date
    field :start_time, String, null: false, method: :formatted_start_time
    field :end_time, String, null: false, method: :formatted_end_time
    field :location, String, null: true
  end
end
