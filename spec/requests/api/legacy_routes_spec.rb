# frozen_string_literal: true

require "rails_helper"

# config/routes/api_legacy.rb keeps old paths alive for published extension
# builds. Api::LegacyRouteCounting adds one to
# calendar_api_legacy_requests_total for each request to such a path.
RSpec.describe "Legacy API routes", type: :request do
  let(:user) { create(:user) }

  def legacy_count(route) = Yabeda.calendar.api_legacy_requests_total.get(route: route) || 0

  it "points each legacy route to an action of its controller" do
    Rails.application.routes.routes.select { |route| route.defaults.key?(:legacy_route) }.each do |route|
      controller = "#{route.defaults[:controller]}_controller".camelize.constantize

      expect(controller.action_methods).to include(route.defaults[:action]),
                                           "#{route.defaults[:legacy_route]} names a missing action"
    end
  end

  context "with an old path" do
    around do |example|
      with_routing do |routes|
        routes.draw do
          namespace :api do
            get "user/old_flags", to: "feature_flags#index", defaults: { legacy_route: "GET user/old_flags" }
            get "user/feature_flags", to: "feature_flags#index"
          end
        end
        example.run
      end
    end

    # Feature flags render no URL, so the action works with the test routes.
    it "answers like the new path, and counts the request" do
      expect { get "/api/user/old_flags", headers: auth_headers_for(user) }
        .to change { legacy_count("GET user/old_flags") }.by(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to have_key("feature_flags")
    end

    it "does not count a request to a current path" do
      expect { get "/api/user/feature_flags", headers: auth_headers_for(user) }
        .not_to change { legacy_count("GET user/old_flags") }
    end
  end

  it "redirects the old GraphQL path with 308, so the client sends the POST again" do
    post "/api/graphql", params: { query: "{ terms { uid } }" }, as: :json

    expect(response).to have_http_status(:permanent_redirect)
    expect(response.headers["Location"]).to eq("http://www.example.com/api/v1/graphql")
  end
end
