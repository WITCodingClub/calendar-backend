# frozen_string_literal: true

module Types
  class SeatsType < BaseObject
    description "Seat counts for a section, from Banner. A nightly job refreshes " \
                "them, so they can be up to a day old. They are not a real-time count."

    field :capacity, Integer, null: true,
          description: "Total seats in the section. Null when Banner returned no enrollment data."
    field :available, Integer, null: true,
          description: "Seats still open. Null when Banner returned no enrollment data."
  end
end
