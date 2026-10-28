# frozen_string_literal: true

module Types
  class WaitlistType < BaseObject
    description "Waitlist counts for a section, from Banner. They refresh with the seat counts, " \
                "so they are not a real-time count."

    field :capacity, Integer, null: true,
          description: "Places on the waitlist. 0 when the section has no waitlist. " \
                       "Null when Banner returned no enrollment data."
    field :available, Integer, null: true,
          description: "Waitlist places still open. Null when Banner returned no enrollment data."
  end
end
