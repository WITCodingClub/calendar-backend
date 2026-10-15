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

  describe "the HTML page" do
    it "uses the built stylesheet, not the Tailwind CDN" do
      get "/404", headers: browser

      expect(response.body).not_to include("cdn.tailwindcss.com")
      expect(response.body).to include('rel="stylesheet"', "/assets/tailwind")
    end

    it "has a main landmark and a skip link to it" do
      get "/404", headers: browser

      page = Nokogiri::HTML(response.body)
      expect(page.at_css("main#error-main")).to be_present
      expect(page.at_css('a[href="#error-main"]').text).to eq("Skip to content")
    end

    it "shows the code and the title in the page and the browser tab" do
      get "/500", headers: browser

      page = Nokogiri::HTML(response.body)
      expect(page.at_css("h1").text).to eq("Something went wrong")
      expect(page.at_css("title").text).to start_with("500 Something went wrong")
    end

    # The 422 and 500 pages render the partial with no block, so its yield
    # must add nothing.
    it "renders the page once when the partial has no extra actions" do
      get "/422", headers: browser

      page = Nokogiri::HTML(response.body)
      expect(page.css("main").size).to eq(1)
      expect(page.css("h1").size).to eq(1)
      expect(page.css("main a").map(&:text)).to eq([ "Go to home page", "calendarwit@gmail.com" ])
    end

    it "links to the API reference and to help from the not found page" do
      get "/404", headers: browser

      expect(response.body).to include('href="/docs/api"', "mailto:calendarwit@gmail.com")
    end

    it "sends a visitor who is not signed in to the home page" do
      get "/404", headers: browser

      page = Nokogiri::HTML(response.body)
      expect(page.at_css("a.m3-btn-filled").text).to eq("Go to home page")
      expect(response.body).not_to include("Back to dashboard")
    end

    context "when the user is signed in" do
      before { sign_in create(:user) }

      it "sends the user to the dashboard" do
        get "/404", headers: browser

        page = Nokogiri::HTML(response.body)
        expect(page.at_css("a.m3-btn-filled")["href"]).to eq("/dashboard")
        expect(page.at_css("a.m3-btn-filled").text).to eq("Back to dashboard")
      end

      it "shows a sign out button on the unauthorized page" do
        get "/unauthorized"

        expect(Nokogiri::HTML(response.body).at_css("form button").text).to eq("Sign out")
      end
    end

    it "shows a sign in link on the unauthorized page to a visitor" do
      get "/unauthorized"

      expect(response.body).to include(">Sign in</a>")
    end

    # A 500 can come from a database outage. The session lookup then fails,
    # and the page must render anyway.
    it "renders the 500 page as signed out when the session lookup fails" do
      allow_any_instance_of(ErrorsController).to receive(:user_signed_in?) # rubocop:disable RSpec/AnyInstance
        .and_raise(ActiveRecord::ConnectionNotEstablished)
      allow(Rails.error).to receive(:report)

      get "/500", headers: browser

      expect(response).to have_http_status(:internal_server_error)
      expect(response.body).to include("Go to home page")
      expect(Rails.error).to have_received(:report)
        .with(an_instance_of(ActiveRecord::ConnectionNotEstablished), handled: true, context: { error_page: "internal_server_error" })
    end
  end
end
