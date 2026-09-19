# frozen_string_literal: true

module Types
  class InstructorType < BaseObject
    description "A faculty member who teaches sections"

    connection_type_class Types::BaseConnection
    edge_type_class Types::BaseEdge

    field :pub_id, String, null: false, method: :public_id
    field :name, String, null: false, method: :full_name
    field :first_name, String, null: false
    field :last_name, String, null: false
    field :title, String, null: true
    field :department, String, null: true
    field :school, String, null: true
    field :rmp, RmpRatingType, null: true

    # Each call runs its own vector query, so the field costs more than a
    # column and says so. It is empty until the instructor has been embedded.
    field :similar, [ InstructorType ], null: false, complexity: 10,
          description: "Instructors who teach something close to what this one teaches" do
      argument :limit, Integer, required: false, default_value: Embeddable::DEFAULT_SIMILAR_LIMIT
      directive Directives::ListSize, slicing_arguments: [ "limit" ],
                assumed_size: Embeddable::MAX_SIMILAR_LIMIT, require_one_slicing_argument: false
    end

    def similar(limit:)
      object.similar_instructors(limit: limit.clamp(1, Embeddable::MAX_SIMILAR_LIMIT))
    end

    # Email and phone are intentionally absent: this schema is unauthenticated.
    #
    # Returns a plain hash: graphql-ruby resolves object fields from symbol
    # keys, and this avoids depending on ostruct, which is no longer a default gem.
    def rmp
      ::Catalog::InstructorSerializer.rmp_for(object)
    end
  end
end
