# frozen_string_literal: true

module Types
  # Adds totalCount to every connection in the schema. Clients paginating the
  # catalog need the total to render "showing 50 of 1174".
  class BaseConnection < GraphQL::Types::Relay::BaseConnection
    field :total_count, Integer, null: false,
          description: "Total matching records, ignoring pagination"

    def total_count
      object.items.size
    end
  end
end
