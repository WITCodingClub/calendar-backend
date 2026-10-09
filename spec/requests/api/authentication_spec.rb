# frozen_string_literal: true

require "rails_helper"

# An API controller requires a token only for the actions that call
# authenticate_with_token. A missing call makes an action public without
# notice, so this spec sends a request with no token to every API route. Each
# route must answer 401, unless its action is in PUBLIC_ACTIONS. A new public
# action needs a line here, so review sees it.
RSpec.describe "API authentication" do
  PUBLIC_ACTIONS = %w[
    api/csp_reports#create
    api/extension_events#create
    api/graphql#execute
    api/onboardings#create
    api/passkeys#authenticate
    api/passkeys#authentication_options
    api/passkeys#exchange
    api/terms#current_and_next
    api/v1/catalog/instructors#index
    api/v1/catalog/instructors#show
    api/v1/catalog/instructors#similar
    api/v1/catalog/reviews#index
    api/v1/catalog/sections#index
    api/v1/catalog/sections#show
    api/v1/catalog/sections#similar
    api/v1/catalog/subjects#index
    api/v1/catalog/terms#current
    api/v1/catalog/terms#index
    api/v1/catalog/terms#next
    api/v1/catalog/terms#show
  ].freeze

  api_routes = Rails.application.routes.routes.filter_map do |route|
    controller = route.defaults[:controller]
    next unless controller&.start_with?("api/")

    verb = route.verb.split("|").first.presence || "GET"
    path = route.path.spec.to_s
                .delete_suffix("(.:format)")
                .sub("*path", "not-a-route")
                .gsub(/:\w+/, "1")

    { action: "#{controller}##{route.defaults[:action]}", verb: verb, path: path }
  end

  it "lists only actions that have a route" do
    expect(PUBLIC_ACTIONS - api_routes.pluck(:action)).to be_empty
  end

  api_routes.reject { |route| PUBLIC_ACTIONS.include?(route[:action]) }.each do |route|
    it "requires a token for #{route[:verb]} #{route[:path]} (#{route[:action]})" do
      process route[:verb].downcase.to_sym, route[:path], as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["code"]).to eq("AUTH_MISSING")
    end
  end

  api_routes.select { |route| PUBLIC_ACTIONS.include?(route[:action]) }.each do |route|
    it "does not require a token for #{route[:verb]} #{route[:path]} (#{route[:action]})" do
      process route[:verb].downcase.to_sym, route[:path], as: :json

      # Some public actions answer 401 for bad credentials of their own, such
      # as a failed passkey, so the check is for the token error only.
      expect(response.body).not_to include("AUTH_MISSING")
    end
  end
end
