# frozen_string_literal: true

module Types
  class ReviewType < BaseObject
    description "One Rate My Professors review of a WIT instructor"

    connection_type_class Types::BaseConnection
    edge_type_class Types::BaseEdge

    field :pub_id, String, null: false, method: :public_id
    field :instructor, InstructorType, null: true, method: :faculty
    field :course_name, String, null: true
    field :comment, String, null: false
    field :clarity_rating, Integer, null: true
    field :difficulty_rating, Integer, null: true
    field :would_take_again, Boolean, null: true
    field :sentiment, String, null: false, method: :overall_sentiment
    field :tags, [ String ], null: false
    field :thumbs_up, Integer, null: true, method: :thumbs_up_total
    field :thumbs_down, Integer, null: true, method: :thumbs_down_total
    field :rated_on, GraphQL::Types::ISO8601Date, null: true
    field :source, String, null: false,
          description: "Where the text comes from, for credit and for a link back"

    def tags
      ::Catalog::ReviewSerializer.new(object).as_json[:tags]
    end

    def rated_on
      object.rating_date&.to_date
    end

    def source
      ::Catalog::ReviewSerializer::SOURCE
    end
  end
end
