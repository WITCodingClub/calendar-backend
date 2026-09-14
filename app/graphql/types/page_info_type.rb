# frozen_string_literal: true

module Types
  # The Relay PageInfo type, with the same name and fields as the one in
  # graphql-ruby. Its fields use BaseField, so they carry @cost like every other
  # field.
  class PageInfoType < BaseObject
    graphql_name "PageInfo"

    include GraphQL::Types::Relay::PageInfoBehaviors
  end
end
