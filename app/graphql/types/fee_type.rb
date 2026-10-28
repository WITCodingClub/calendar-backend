# frozen_string_literal: true

module Types
  class FeeType < BaseObject
    description "A fee that Banner lists for a course, such as a Follett Access fee for the course materials"

    field :level, String, null: true, description: "e.g. \"Undergraduate\""
    field :description, String, null: true, description: "e.g. \"Follett Access\""
    field :amount_cents, Integer, null: false, description: "The amount in US cents"

    def level        = object["level"]
    def description  = object["description"]
    def amount_cents = object["amount_cents"]
  end
end
