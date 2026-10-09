# frozen_string_literal: true

require "rails_helper"

# config/routes/api/legacy.rb keeps old paths alive for published extension
# builds. Each request to an old path adds one to
# calendar_api_legacy_requests_total.
RSpec.describe "Legacy API routes", type: :request do
  let(:user) { create(:user) }

  routes = Rails.application.routes.routes.select { |route| route.defaults.key?(:legacy_route) }

  def legacy_count(route) = Yabeda.calendar.api_legacy_requests_total.get(route: route) || 0

  it "has legacy routes" do
    expect(routes).not_to be_empty
  end

  it "points each legacy route to an action of its controller" do
    routes.each do |route|
      controller = "#{route.defaults[:controller]}_controller".camelize.constantize

      expect(controller.action_methods).to include(route.defaults[:action]),
                                           "#{route.defaults[:legacy_route]} names a missing action"
    end
  end

  it "answers an old path like its new path, and counts the request" do
    expect { get "/api/user/email", headers: auth_headers_for(user) }
      .to change { legacy_count("GET user/email") }.by(1)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("email" => user.email)
  end

  it "does not count a request to a current path" do
    expect { get "/api/user", headers: auth_headers_for(user) }
      .not_to change { legacy_count("GET user/email") }
  end

  it "keeps the old POST for processed events" do
    term = create(:term)

    post "/api/user/processed_events", params: { term_uid: term.uid }, headers: auth_headers_for(user), as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("classes" => [])
  end

  it "redirects the old GraphQL path with 308, so the client sends the POST again" do
    post "/api/graphql", params: { query: "{ terms { uid } }" }, as: :json

    expect(response).to have_http_status(:permanent_redirect)
    expect(response.headers["Location"]).to eq("http://www.example.com/api/v1/graphql")
  end
end
