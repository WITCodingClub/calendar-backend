# frozen_string_literal: true

module Types
  class InstructorType < BaseObject
    description "A faculty member who teaches sections"

    connection_type_class Types::BaseConnection

    field :pub_id, String, null: false, method: :public_id
    field :name, String, null: false, method: :full_name
    field :first_name, String, null: false
    field :last_name, String, null: false
    field :title, String, null: true
    field :department, String, null: true
    field :school, String, null: true
    field :rmp, RmpRatingType, null: true

    # Email and phone are intentionally absent: this schema is unauthenticated.
    #
    # Returns a plain hash: graphql-ruby resolves object fields from symbol
    # keys, and this avoids depending on ostruct, which is no longer a default gem.
    def rmp
      ::Catalog::InstructorSerializer.rmp_for(object)
    end
  end
end
