# frozen_string_literal: true

module Api
  # POST /api/graphql — public catalog GraphQL endpoint.
  class GraphqlController < Api::V1::PublicController
    def execute
      result = CatalogSchema.execute(
        params[:query],
        variables:      prepare_variables(params[:variables]),
        operation_name: params[:operationName],
        context:        {}
      )

      render json: result
    rescue JSON::ParserError => e
      render json: { errors: [ { message: "Invalid variables JSON: #{e.message}" } ], data: nil },
             status: :bad_request
    end

    private

    # Variables arrive as a JSON string from some clients and as a hash from others.
    def prepare_variables(variables)
      case variables
      when String                       then variables.present? ? JSON.parse(variables) : {}
      when ActionController::Parameters then variables.to_unsafe_h
      when Hash                         then variables
      when nil                          then {}
      else raise ArgumentError, "Unexpected variables: #{variables.class}"
      end
    end
  end
end
