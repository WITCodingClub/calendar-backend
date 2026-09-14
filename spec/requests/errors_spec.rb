# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Error pages" do
  let(:browser) { { "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" } }
  # curl and most agents. A request spec otherwise sends an Accept header that
  # lists text/html.
  let(:agent) { { "Accept" => "*/*" } }

  it "renders the not found page as HTML for a browser" do
    get "/404", headers: browser

    expect(response).to have_http_status(:not_found)
    expect(response.media_type).to eq("text/html")
  end

  describe "a path with no route" do
    let(:path) { "/some-path-that-does-not-exist" }

    # The test environment shows detailed exceptions, so DebugExceptions would
    # answer with its own routing error page. Production sends the request to
    # config.exceptions_app instead.
    around do |example|
      env_config = Rails.application.env_config
      detailed   = env_config["action_dispatch.show_detailed_exceptions"]
      env_config["action_dispatch.show_detailed_exceptions"] = false
      example.run
    ensure
      env_config["action_dispatch.show_detailed_exceptions"] = detailed
    end

    it "returns 404 with a markdown body that points agents to the index files" do
      get path, headers: agent

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("text/markdown")
      expect(response.body).to start_with("# 404 Not Found\n")
      expect(response.body).to include(
        "(http://example.com/llms.txt)", "(http://example.com/sitemap.xml)", "(http://example.com/docs/api.md)"
      )
    end

    it "returns markdown to a client that ranks markdown above HTML" do
      get path, headers: { "Accept" => "text/markdown, text/html;q=0.9, */*;q=0.8" }

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("text/markdown")
    end

    it "returns the HTML page to a browser" do
      get path, headers: browser

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("text/html")
    end

    it "tells a cache that the body depends on Accept" do
      get path, headers: agent

      expect(response.headers["Vary"]).to include("Accept")
    end

    # ApplicationController's modern-browser guard answered curl with 406.
    it "returns 404, not 406, to curl" do
      get path, headers: agent.merge("User-Agent" => "curl/8.21.0")

      expect(response).to have_http_status(:not_found)
    end
  end

  it "returns 404, not 500, for a missing image" do
    get "/404.png", headers: { "Accept" => "image/avif,image/webp,*/*;q=0.8" }

    expect(response).to have_http_status(:not_found)
    expect(response.media_type).to eq("text/markdown")
  end

  it "returns 404, not 500, for a missing font" do
    get "/404.woff2"

    expect(response).to have_http_status(:not_found)
  end

  it "renders the unauthorized page as HTML" do
    get "/unauthorized"

    expect(response).to have_http_status(:forbidden)
    expect(response.media_type).to eq("text/html")
  end

  it "returns 422 for a JSON request" do
    get "/422.json"

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "returns 500 for a PHP probe" do
    get "/500.php"

    expect(response).to have_http_status(:internal_server_error)
  end
end
