# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::UserExtensionConfigs", type: :request do
  let(:user) { create(:user) }
  let(:token) { JsonWebTokenService.encode(user_id: user.id) }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }

  describe "GET /api/user/extension_config" do
    context "when user has extension config" do
      let!(:config) do
        create(:user_extension_config,
               user: user,
               military_time: true,
               default_color_lecture: GoogleColors::WITCC_PEACOCK,  # WITCC hex
               default_color_lab: GoogleColors::WITCC_BANANA)       # WITCC hex
      end

      it "returns the config with colors converted to Google event hex" do
        get "/api/user/extension_config", headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["military_time"]).to be true
        # Should return Google event colors, not WITCC colors
        expect(json["default_color_lecture"]).to eq(GoogleColors::EVENT_PEACOCK)  # Google hex
        expect(json["default_color_lab"]).to eq(GoogleColors::EVENT_BANANA)       # Google hex
      end
    end

    context "when user has no extension config" do
      it "returns not found" do
        get "/api/user/extension_config", headers: headers

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("User extension config not found")
      end
    end
  end

  describe "PUT /api/user/extension_config" do
    context "when creating new config with Google event colors" do
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

    context "when updating existing config with Google event colors" do
      let!(:config) do
        create(:user_extension_config,
               user: user,
               default_color_lecture: GoogleColors::WITCC_TOMATO,
               default_color_lab: GoogleColors::WITCC_BASIL)
      end

      it "converts and updates colors" do
        put "/api/user/extension_config", params: {
          default_color_lecture: GoogleColors::EVENT_BLUEBERRY,  # Google hex
          default_color_lab: GoogleColors::EVENT_SAGE            # Google hex
        }, headers: headers

        expect(response).to have_http_status(:ok)

        config.reload
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
