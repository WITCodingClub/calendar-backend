# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::UserExtensionConfig", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers_for(user) }

  def json = JSON.parse(response.body)

  before do
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
  end

  describe "GET /api/user/extension_config" do
    it "lists only the categories that sync" do
      get "/api/user/extension_config", headers: headers

      ids = json["available_university_event_categories"].pluck("id")
      expect(ids).to eq(UniversityCalendarEvent::SYNCABLE_CATEGORIES)
      expect(ids).not_to include("campus_event")
    end
  end

  describe "PUT /api/user/extension_config" do
    it "saves custom default colors in lowercase" do
      put "/api/user/extension_config",
          params: { default_color_lecture: "#1A2B3C", default_color_lab: "#abcdef" },
          headers: headers,
          as: :json

      expect(response).to have_http_status(:ok)

      get "/api/user/extension_config", headers: headers

      expect(json).to include("default_color_lecture" => "#1a2b3c", "default_color_lab" => "#abcdef")
    end

    it "drops university event categories that no longer sync" do
      put "/api/user/extension_config",
          params: { university_event_categories: %w[deadline campus_event exhibit] },
          headers: headers,
          as: :json

      expect(user.user_extension_config.reload.university_event_categories).to eq(%w[deadline])
    end

    it "rejects a default color that is not a color" do
      put "/api/user/extension_config", params: { default_color_lab: "banana" }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.user_extension_config.reload.default_color_lab).to eq(GoogleColors::BANANA)
    end
  end
end
