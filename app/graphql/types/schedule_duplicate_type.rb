# frozen_string_literal: true

module Types
  class ScheduleDuplicateType < BaseObject
    description "The same course chosen twice with the same schedule type"

    field :course_code, String, null: false, description: "e.g. \"COMP 2350\""
    field :crns, [ Integer ], null: false
  end
end
