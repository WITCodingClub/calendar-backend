# frozen_string_literal: true

module Types
  class SeatsType < BaseObject
    description "Seat counts for a section. The Banner catalog import does not " \
                "populate these yet, so both fields are usually null."

    field :capacity, Integer, null: true
    field :available, Integer, null: true
  end
end
