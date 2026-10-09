# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Notifications", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/user/notifications" do
    it "shows that notifications are on" do
      get "/api/user/notifications", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("notifications_disabled" => false, "notifications_disabled_until" => nil)
    end
  end

  describe "PATCH /api/user/notifications" do
    it "turns notifications off for a duration" do
      freeze_time do
        patch "/api/user/notifications", params: { disabled: true, duration: 3600 }, headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        expect(user.reload.notifications_disabled?).to be(true)
        expect(user.notifications_disabled_until).to eq(1.hour.from_now)
      end
    end

    it "turns notifications on again and starts a sync" do
      user.disable_notifications!

      expect do
        patch "/api/user/notifications", params: { disabled: false }, headers: headers, as: :json
      end.to have_enqueued_job(CourseCalendars::SyncJob)

      expect(response).to have_http_status(:ok)
      expect(user.reload.notifications_disabled?).to be(false)
    end

    it "answers BAD_REQUEST without disabled" do
      patch "/api/user/notifications", params: {}, headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to eq("error" => "disabled is required", "code" => "BAD_REQUEST")
    end

    it "refuses a negative duration" do
      patch "/api/user/notifications", params: { disabled: true, duration: -1 }, headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(user.reload.notifications_disabled?).to be(false)
    end
  end
end
