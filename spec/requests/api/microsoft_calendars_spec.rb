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

    it "carries the placement in the state, and drops a value it does not know", :microsoft_graph do
      Flipper.enable_actor(FlipperFlags::MICROSOFT_GRAPH_CALENDAR, user)
      state_for = lambda do |placement|
        post "/api/user/microsoft_calendar", params: { placement: placement }, headers: auth_headers_for(user)
        url = URI(JSON.parse(response.body)["oauth_url"])
        MicrosoftGraph::OauthState.verify(URI.decode_www_form(url.query).to_h["state"])
      end

      expect(state_for.call("primary")).to include("placement" => "primary")
      expect(state_for.call("shared")).not_to have_key("placement")
    end

    it "needs a token" do
      post "/api/user/microsoft_calendar"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/user/microsoft_calendar" do
    include ActiveJob::TestHelper

    it "answers 404 while the provider is off" do
      patch "/api/user/microsoft_calendar", params: { placement: "primary" }, headers: auth_headers_for(user)

      expect(response).to have_http_status(:not_found)
    end

    context "when the provider is on", :microsoft_graph do
      before { Flipper.enable_actor(FlipperFlags::MICROSOFT_GRAPH_CALENDAR, user) }

      it "starts the move and answers 202" do
        create(:oauth_credential, :microsoft, user: user)

        expect { patch "/api/user/microsoft_calendar", params: { placement: "primary" }, headers: auth_headers_for(user) }
          .to have_enqueued_job(MicrosoftGraphCalendarPlacementJob).with(user, "primary")

        expect(response).to have_http_status(:accepted)
        expect(JSON.parse(response.body)).to include("placement" => "primary")
      end

      it "refuses a placement it does not know" do
        create(:oauth_credential, :microsoft, user: user)

        expect { patch "/api/user/microsoft_calendar", params: { placement: "shared" }, headers: auth_headers_for(user) }
          .not_to have_enqueued_job(MicrosoftGraphCalendarPlacementJob)

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "answers 404 when no Microsoft calendar is connected" do
        patch "/api/user/microsoft_calendar", params: { placement: "primary" }, headers: auth_headers_for(user)

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
