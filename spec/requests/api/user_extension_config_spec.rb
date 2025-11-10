# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::UserExtensionConfigs", type: :request do
  let(:user) { create(:user) }
  let(:token) { JsonWebTokenService.encode(user_id: user.id) }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }

  before do
    # Enable the v1 feature flag for API access
    Flipper.enable(FlipperFlags::V1, user)
    # Stub the background job to prevent it from running during tests
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
  end

  describe "GET /api/user/extension_config" do
    context "when user has extension config with custom settings" do
      before do
        # User automatically gets a config on creation, so update it
        user.user_extension_config.update!(
          military_time: true,
          default_color_lecture: GoogleColors::WITCC_PEACOCK,  # WITCC hex
          default_color_lab: GoogleColors::WITCC_BANANA        # WITCC hex
        )
      end

      it "returns the config with WITCC colors as stored" do
        get "/api/user/extension_config", headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["military_time"]).to be true
        # Should return WITCC colors as stored in database
        expect(json["default_color_lecture"]).to eq(GoogleColors::WITCC_PEACOCK)  # WITCC hex
        expect(json["default_color_lab"]).to eq(GoogleColors::WITCC_BANANA)       # WITCC hex
      end
    end

    context "when user has default extension config" do
      it "returns the config with default values" do
        get "/api/user/extension_config", headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["military_time"]).to be false
        # Default colors in database are WITCC colors
        expect(json["default_color_lecture"]).to eq(GoogleColors::WITCC_PEACOCK)  # Default lecture color (#039be5)
        expect(json["default_color_lab"]).to eq(GoogleColors::WITCC_BANANA)       # Default lab color (#f6bf26)
      end
    end
  end

  describe "PUT /api/user/extension_config" do
    context "when updating config with Google event colors" do
      it "converts Google event colors to WITCC colors before saving" do
        put "/api/user/extension_config", params: {
          military_time: false,
          default_color_lecture: GoogleColors::EVENT_PEACOCK,  # Google hex input
          default_color_lab: GoogleColors::EVENT_BANANA        # Google hex input
        }, headers: headers

        expect(response).to have_http_status(:ok)

        config = user.reload.user_extension_config
        # Should store WITCC colors in database
        expect(config.default_color_lecture).to eq(GoogleColors::WITCC_PEACOCK)
        expect(config.default_color_lab).to eq(GoogleColors::WITCC_BANANA)
      end
    end

    context "when updating existing config with different Google event colors" do
      before do
        # Update the existing config first
        user.user_extension_config.update!(
          default_color_lecture: GoogleColors::WITCC_TOMATO,
          default_color_lab: GoogleColors::WITCC_BASIL
        )
      end

      it "converts and updates colors" do
        put "/api/user/extension_config", params: {
          default_color_lecture: GoogleColors::EVENT_BLUEBERRY,  # Google hex
          default_color_lab: GoogleColors::EVENT_SAGE            # Google hex
        }, headers: headers

        expect(response).to have_http_status(:ok)

        config = user.reload.user_extension_config
        # Should store WITCC colors in database
        expect(config.default_color_lecture).to eq(GoogleColors::WITCC_BLUEBERRY)
        expect(config.default_color_lab).to eq(GoogleColors::WITCC_SAGE)
      end
    end

    context "when color doesn't map to WITCC color" do
      it "stores the original color" do
        custom_color = "#123456"

        put "/api/user/extension_config", params: {
          default_color_lecture: custom_color
        }, headers: headers

        expect(response).to have_http_status(:ok)

        config = user.reload.user_extension_config
        # Should store the original color if no mapping exists
        expect(config.default_color_lecture).to eq(custom_color)
      end
    end
  end
end
