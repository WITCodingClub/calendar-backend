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

    # One grouped count for every term in the query, not one count per term.
    def section_count
      counts = context[:term_section_counts] ||= Course.active.group(:term_id).count
      counts.fetch(object.id, 0)
    end
  end
end
