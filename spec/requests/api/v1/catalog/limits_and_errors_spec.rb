# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Catalog API rate limits and errors", type: :request do
  it "tells the client its quota with the RateLimit fields" do
    get "/api/v1/catalog/terms"

    expect(response).to have_http_status(:ok)
    expect(response.headers["ratelimit-policy"]).to include('"catalog/ip";q=300;w=60')
    expect(response.headers["ratelimit"]).to match(/"catalog\/ip";r=\d+;t=\d+/)
  end

  it "returns the typed error object for an unexpected error" do
    allow(Term).to receive(:reverse_chronological).and_raise(StandardError, "database is down")

    get "/api/v1/catalog/terms"

    expect(response).to have_http_status(:internal_server_error)
    expect(response.parsed_body).to eq("error" => "Internal server error", "code" => "INTERNAL_ERROR")
  end

  it "keeps the specific error for a record that does not exist" do
    get "/api/v1/catalog/terms/999999"

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body["code"]).to eq("NOT_FOUND")
  end
end
