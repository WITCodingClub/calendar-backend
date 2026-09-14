# frozen_string_literal: true

module Types
  # The edge type of every connection. It is the same as the Relay edge in
  # graphql-ruby, but its cursor and node fields use BaseField, so they carry
  # @cost like every other field.
  class BaseEdge < BaseObject
    include GraphQL::Types::Relay::EdgeBehaviors
  end
end
