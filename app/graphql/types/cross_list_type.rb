# frozen_string_literal: true

module Types
  class CrossListType < BaseObject
    description "Sections of different courses that meet together, such as an undergraduate " \
                "and a graduate studio. Banner gives the group one set of seats."

    field :identifier, String, null: false,
          description: "Banner's cross-list group, e.g. \"01\". It is unique only in its term."
    field :crns, [ Integer ], null: false,
          description: "CRNs of the other sections in the group, in the same term."
    field :seats, SeatsType, null: false,
          description: "Seat counts for the whole group."
  end
end
