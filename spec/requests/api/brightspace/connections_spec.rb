# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Brightspace connection API", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers_for(user) }

  def json = response.parsed_body

  before { Flipper.enable_actor(FlipperFlags::BRIGHTSPACE, user) }

  describe "GET /api/user/brightspace_connection" do
    it "returns null when nothing is linked" do
      get "/api/user/brightspace_connection", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("connection" => nil)
    end

    it "returns the active connection" do
      connection = create(:brightspace_connection, user: user)

      get "/api/user/brightspace_connection", headers: headers

      expect(json["connection"]).to include("id" => connection.public_id, "host" => connection.host,
                                            "learner_id" => connection.learner_id, "status" => "active")
    end

    it "answers 404 while the flag is off" do
      Flipper.disable_actor(FlipperFlags::BRIGHTSPACE, user)

      get "/api/user/brightspace_connection", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      get "/api/user/brightspace_connection"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/user/brightspace_connection" do
    it "links the account" do
      post "/api/user/brightspace_connection", params: { host: "brightspace.example.edu", learner_id: "98765" },
                                               headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["connection"]).to include("host" => "brightspace.example.edu", "learner_id" => "98765", "status" => "active")
      expect(json["connection"]["id"]).to start_with("bsc_")
    end

    it "answers 400 without a learner id" do
      post "/api/user/brightspace_connection", params: { host: "brightspace.example.edu" }, headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(json["code"]).to eq("VALIDATION_FAILED")
    end

    it "answers 422 for a host that is not a host name" do
      post "/api/user/brightspace_connection", params: { host: "not a host", learner_id: "1" }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to match(/Host must be a host name/)
    end
  end

  describe "DELETE /api/user/brightspace_connection" do
    it "disconnects and keeps the data" do
      connection = create(:brightspace_connection, user: user)
      offering = create(:brightspace_course_offering, connection: connection)

      delete "/api/user/brightspace_connection", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(connection.reload).to be_disconnected
      expect(offering.reload).to be_persisted
    end

    it "queues a calendar sync, which removes the account's deadlines" do
      create(:brightspace_connection, user: user)
      create(:oauth_credential, user: user)
      allow(GoogleCalendarSyncJob).to receive(:perform_later)

      delete "/api/user/brightspace_connection", headers: headers

      expect(GoogleCalendarSyncJob).to have_received(:perform_later).with(user, force: false)
    end

    it "answers 404 when nothing is linked" do
      delete "/api/user/brightspace_connection", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
