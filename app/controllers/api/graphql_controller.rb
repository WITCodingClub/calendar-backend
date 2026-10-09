# frozen_string_literal: true

module Api
  # POST /api/v1/graphql — public catalog GraphQL endpoint.
  class GraphqlController < Api::V1::PublicController
    def execute
      result = CatalogSchema.execute(
        params[:query],
        variables:      prepare_variables(params[:variables]),
        operation_name: params[:operationName],
        context:        { request: request }
      )

      # Analyzers::SemanticSearchLimit refused a semantic search because the
      # IP address used up the catalog/semantic budget.
      if request.env["rack.attack.matched"] == "catalog/semantic"
        response.headers["Retry-After"] = Rack::Attack.seconds_until_reset(request.env["rack.attack.match_data"]).to_s
        render json: result, status: :too_many_requests
      else
        render json: result
      end
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
