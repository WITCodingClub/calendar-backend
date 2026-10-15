# frozen_string_literal: true

require "rails_helper"

# Issue #684: Cloudflare caches catalog responses and ignores Vary: Origin, so
# the first response for a URL is served to every origin for up to an hour.
# Each origin must get the same cache and CORS headers.
RSpec.describe "Catalog API edge cache", type: :request do
  [ nil, "https://example.com", "http://localhost:3001" ].each do |origin|
    it "sends public cache headers and allows any origin (Origin: #{origin || 'none'})" do
      get "/api/v1/catalog/terms", headers: origin ? { "Origin" => origin } : {}

      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to eq("max-age=3600, public")
      expect(response.headers["Access-Control-Allow-Origin"]).to eq("*")
      expect(response.headers).not_to have_key("Access-Control-Allow-Credentials")
      expect(response.headers).not_to have_key("Set-Cookie")
    end
  end

  it "keeps credentials for localhost on the rest of the API" do
    get "/api/user", headers: { "Origin" => "http://localhost:3001" }

    expect(response.headers["Access-Control-Allow-Origin"]).to eq("http://localhost:3001")
    expect(response.headers["Access-Control-Allow-Credentials"]).to eq("true")
  end
end
