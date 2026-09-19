# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::MicrosoftCalendars", type: :request do
  let(:user) { create(:user) }

  after { Flipper.disable(FlipperFlags::MICROSOFT_GRAPH_CALENDAR) }

  describe "POST /api/user/microsoft_calendar" do
    it "answers 404 while the provider is off" do
      post "/api/user/microsoft_calendar", headers: auth_headers_for(user)

      expect(response).to have_http_status(:not_found)
    end

    it "answers 404 when the flag is on but no Entra client is configured" do
      Flipper.enable_actor(FlipperFlags::MICROSOFT_GRAPH_CALENDAR, user)

      post "/api/user/microsoft_calendar", headers: auth_headers_for(user)

      expect(response).to have_http_status(:not_found)
    end

    it "returns a start URL that carries a signed state", :microsoft_graph do
      Flipper.enable_actor(FlipperFlags::MICROSOFT_GRAPH_CALENDAR, user)

      post "/api/user/microsoft_calendar", headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)
      url   = URI(JSON.parse(response.body)["oauth_url"])
      state = URI.decode_www_form(url.query).to_h["state"]
      expect(url.path).to eq("/auth/microsoft_graph")
      expect(MicrosoftGraph::OauthState.verify(state)).to include("user_id" => user.id)
    end

    it "needs a token" do
      post "/api/user/microsoft_calendar"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
