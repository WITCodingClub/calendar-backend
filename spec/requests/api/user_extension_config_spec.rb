# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::UserExtensionConfig", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers_for(user) }

  def json = JSON.parse(response.body)

  before do
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
    Flipper.enable(FlipperFlags::V1)
  end

  after { Flipper.disable(FlipperFlags::V1) }

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

    it "rejects a default color that is not a color" do
      put "/api/user/extension_config", params: { default_color_lab: "banana" }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.user_extension_config.reload.default_color_lab).to eq(GoogleColors::BANANA)
    end
  end
end
