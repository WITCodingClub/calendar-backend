# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Connecting a Microsoft calendar", type: :request do
  let(:user)  { create(:user) }
  let(:state) { MicrosoftGraph::OauthState.generate(user_id: user.id) }

  after { Flipper.disable(FlipperFlags::MICROSOFT_GRAPH_CALENDAR) }

  it "answers 404 while the provider is off" do
    get "/auth/microsoft_graph", params: { state: state }

    expect(response).to have_http_status(:not_found)
  end

  context "when the provider is on", :microsoft_graph do
    before { Flipper.enable_actor(FlipperFlags::MICROSOFT_GRAPH_CALENDAR, user) }

    it "answers 404 for a state that was not signed here" do
      get "/auth/microsoft_graph", params: { state: "forged" }

      expect(response).to have_http_status(:not_found)
    end

    it "sends the browser to Microsoft with PKCE" do
      get "/auth/microsoft_graph", params: { state: state }

      expect(response).to have_http_status(:redirect)
      location = URI(response.location)
      query    = URI.decode_www_form(location.query).to_h
      expect(location.host).to eq("login.microsoftonline.com")
      expect(query).to include("state" => state, "code_challenge_method" => "S256",
                               "redirect_uri" => "http://www.example.com/auth/microsoft_graph/callback")
    end

    it "stores the tokens, creates the calendar and reports success" do
      token = stub_request(:post, MicrosoftGraphHelpers::TOKEN_URL)
              .with(body: hash_including("grant_type" => "authorization_code", "code" => "auth-code"))
              .to_return(graph_json_response("token_success"))
      stub_request(:post, "#{MicrosoftGraphHelpers::GRAPH_URL}/me/calendars").to_return(graph_json_response("calendar_created"))

      get "/auth/microsoft_graph", params: { state: state }
      get "/auth/microsoft_graph/callback", params: { state: state, code: "auth-code" }

      expect(token).to have_been_requested
      expect(response).to redirect_to("/oauth/success?email=student%40example.edu&calendar_id=AAMkSyntheticCalendarNew")

      credential = user.oauth_credentials.microsoft.sole
      expect(credential).to have_attributes(
        uid: "00000000-0000-0000-0000-000000000001", email: "student@example.edu",
        access_token: "synthetic-access-token", refresh_token: "synthetic-refresh-token"
      )
      expect(credential.course_calendar).to have_attributes(provider: "microsoft", external_calendar_id: "AAMkSyntheticCalendarNew")
    end

    it "refuses a callback that did not start in this browser" do
      get "/auth/microsoft_graph/callback", params: { state: state, code: "auth-code" }

      expect(URI(response.location).path).to eq("/oauth/failure")
      expect(user.oauth_credentials.microsoft).to be_empty
    end

    it "reports a sign-in that Microsoft refused" do
      get "/auth/microsoft_graph", params: { state: state }
      get "/auth/microsoft_graph/callback", params: { state: state, error: "consent_required" }

      expect(URI(response.location).path).to eq("/oauth/failure")
      expect(user.oauth_credentials.microsoft).to be_empty
    end
  end
end
