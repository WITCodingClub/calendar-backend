# frozen_string_literal: true

module Types
  class BuildingType < BaseObject
    description "A campus building"

    field :abbreviation, String, null: false
    field :name, String, null: false
    field :formal_name, String, null: true
  end
end
