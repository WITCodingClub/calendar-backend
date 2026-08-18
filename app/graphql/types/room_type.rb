# frozen_string_literal: true

module Types
  class RoomType < BaseObject
    description "A room inside a campus building"

    field :number, String, null: false
    field :floor, Integer, null: true
    field :building, BuildingType, null: true
  end
end
