# frozen_string_literal: true

module Types
  class TermType < BaseObject
    description "An academic term"

    field :uid, Integer, null: false, description: "Banner term code, e.g. 202710"
    field :name, String, null: false, description: "e.g. \"Fall 2026\""
    field :season, SeasonEnum, null: false
    field :year, Integer, null: false
    field :start_date, GraphQL::Types::ISO8601Date, null: true
    field :end_date, GraphQL::Types::ISO8601Date, null: true
    field :section_count, Integer, null: false

    def section_count
      Course.active.where(term_id: object.id).count
    end
  end
end
