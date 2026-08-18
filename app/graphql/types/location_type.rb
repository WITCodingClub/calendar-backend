# frozen_string_literal: true

module Types
  # Where a meeting happens. Mirrors the "location" object the REST serializer
  # emits so the two API surfaces describe a meeting the same way.
  class LocationType < BaseObject
    description "The building and rooms a meeting is held in"

    # "display" collides with Kernel#display, which graphql-ruby would call
    # instead of reading the hash key, so the resolver is named explicitly.
    #
    # Nullable: a section can be assigned to a placeholder "TBD" building, which
    # has a building record but no usable display name.
    field :display, String, null: true,
          description: "Human-readable building and room, e.g. \"WAT 307\"",
          resolver_method: :resolve_display
    field :building, BuildingType, null: false
    field :rooms, [ RoomType ], null: false

    def resolve_display
      object[:display]
    end
  end
end
