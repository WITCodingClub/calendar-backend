# frozen_string_literal: true

module Types
  class SubjectType < BaseObject
    description "A subject with the number of sections offered"

    field :subject, String, null: false
    field :code, String, null: false
    field :section_count, Integer, null: false
  end
end
