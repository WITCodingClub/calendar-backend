# frozen_string_literal: true

require "rails_helper"

# A param of the wrong type is a client mistake. It answers 400 or 404 through
# render_error, never 500.
RSpec.describe "API params of the wrong type", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }
  let(:body)    { response.parsed_body }

  describe "PUT /api/user/extension_config" do
    it "answers 400 when an enrolled term is a string" do
      put "/api/user/extension_config", params: { enrolled_terms: [ "x" ] }, headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(body).to include("code" => "BAD_REQUEST")
    end
  end

  describe "PATCH /api/user/notifications" do
    it "answers 400 for a duration that is not a whole number" do
      patch "/api/user/notifications", params: { disabled: true, duration: "abc" }, headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(user.reload.notifications_disabled?).to be(false)
    end

    it "answers 400 for a duration that is an object" do
      patch "/api/user/notifications", params: { disabled: true, duration: { a: 1 } }, headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "POST /api/friends/requests" do
    it "answers 400 when friend_email is an array" do
      post "/api/friends/requests", params: { friend_email: [ "a@example.test" ] }, headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "answers 400 when friend_email is an object" do
      post "/api/friends/requests", params: { friend_email: { a: "b" } }, headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "PATCH /api/calendar_preferences/:scope" do
    it "answers 400 when calendar_preference is a string" do
      patch "/api/calendar_preferences/global", params: { calendar_preference: "x" }, headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /api/university_calendar_events" do
    it "answers 400 when a date is an array" do
      get "/api/university_calendar_events?start_date[]=x&end_date[]=y", headers: headers

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /api/university_calendar_events/holidays" do
    it "answers 400 when a date is an array" do
      get "/api/university_calendar_events/holidays?start_date[]=x&end_date[]=y", headers: headers

      expect(response).to have_http_status(:bad_request)
    end
  end
end
