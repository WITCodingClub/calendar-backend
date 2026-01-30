# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::UserExtensionConfigs" do
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
        json = response.parsed_body

        expect(json["military_time"]).to be true
        expect(json["advanced_editing"]).to be false
        # Should return WITCC colors as stored in database
        expect(json["default_color_lecture"]).to eq(GoogleColors::WITCC_PEACOCK)  # WITCC hex
        expect(json["default_color_lab"]).to eq(GoogleColors::WITCC_BANANA)       # WITCC hex
      end
    end

    context "when user has default extension config" do
      it "returns the config with default values" do
        get "/api/user/extension_config", headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body

        expect(json["military_time"]).to be false
        expect(json["advanced_editing"]).to be false
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

    context "when updating advanced_editing setting" do
      it "updates advanced_editing to true" do
        put "/api/user/extension_config", params: {
          advanced_editing: true
        }, headers: headers

        expect(response).to have_http_status(:ok)

        config = user.reload.user_extension_config
        expect(config.advanced_editing).to be true
      end

      it "updates advanced_editing to false" do
        # First set it to true
        user.user_extension_config.update!(advanced_editing: true)

        put "/api/user/extension_config", params: {
          advanced_editing: false
        }, headers: headers

        expect(response).to have_http_status(:ok)

        config = user.reload.user_extension_config
        expect(config.advanced_editing).to be false
      end

      it "can update advanced_editing along with other settings" do
        put "/api/user/extension_config", params: {
          advanced_editing: true,
          military_time: true,
          default_color_lecture: GoogleColors::EVENT_TOMATO
        }, headers: headers

        expect(response).to have_http_status(:ok)

        config = user.reload.user_extension_config
        expect(config.advanced_editing).to be true
        expect(config.military_time).to be true
        expect(config.default_color_lecture).to eq(GoogleColors::WITCC_TOMATO)
      end
    end

    context "when updating university event preferences" do
      it "updates sync_university_events to true" do
        put "/api/user/extension_config", params: {
          sync_university_events: true
        }, headers: headers

        expect(response).to have_http_status(:ok)

        config = user.reload.user_extension_config
        expect(config.sync_university_events).to be true
      end

      it "updates university_event_categories" do
        put "/api/user/extension_config", params: {
          sync_university_events: true,
          university_event_categories: ["campus_event", "academic"]
        }, headers: headers

        expect(response).to have_http_status(:ok)

        config = user.reload.user_extension_config
        expect(config.sync_university_events).to be true
        expect(config.university_event_categories).to contain_exactly("campus_event", "academic")
      end

      it "filters out invalid categories" do
        put "/api/user/extension_config", params: {
          university_event_categories: ["campus_event", "invalid_category", "academic"]
        }, headers: headers

        expect(response).to have_http_status(:ok)

        config = user.reload.user_extension_config
        expect(config.university_event_categories).to contain_exactly("campus_event", "academic")
        expect(config.university_event_categories).not_to include("invalid_category")
      end

      it "triggers calendar sync job when university settings change" do
        expect(GoogleCalendarSyncJob).to receive(:perform_later).with(user, force: true)

        put "/api/user/extension_config", params: {
          sync_university_events: true,
          university_event_categories: ["campus_event"]
        }, headers: headers

        expect(response).to have_http_status(:ok)
      end

      it "clears university_event_categories when sync_university_events is disabled" do
        # First enable sync and set categories
        user.user_extension_config.update!(
          sync_university_events: true,
          university_event_categories: ["campus_event", "academic", "deadline"]
        )

        # Now disable sync via API
        put "/api/user/extension_config", params: {
          sync_university_events: false
        }, headers: headers

        expect(response).to have_http_status(:ok)

        # Verify categories were cleared
        config = user.reload.user_extension_config
        expect(config.sync_university_events).to be false
        expect(config.university_event_categories).to eq([])
      end

      it "clears categories even if categories are specified when disabling sync" do
        # First enable sync and set categories
        user.user_extension_config.update!(
          sync_university_events: true,
          university_event_categories: ["campus_event", "academic"]
        )

        # Try to disable sync while also specifying categories
        # The callback should clear them anyway
        put "/api/user/extension_config", params: {
          sync_university_events: false,
          university_event_categories: ["deadline", "finals"]
        }, headers: headers

        expect(response).to have_http_status(:ok)

        # Categories should be cleared, not set to the new values
        config = user.reload.user_extension_config
        expect(config.sync_university_events).to be false
        expect(config.university_event_categories).to eq([])
      end
    end
  end

  describe "GET /api/user/extension_config with university event settings" do
    before do
      user.user_extension_config.update!(
        sync_university_events: true,
        university_event_categories: ["campus_event", "academic"]
      )
    end

    it "returns university event preferences" do
      get "/api/user/extension_config", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body

      expect(json["sync_university_events"]).to be true
      expect(json["university_event_categories"]).to contain_exactly("campus_event", "academic")
    end

    it "returns available university event categories with descriptions" do
      get "/api/user/extension_config", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body

      expect(json["available_university_event_categories"]).to be_an(Array)
      expect(json["available_university_event_categories"].length).to eq(UniversityCalendarEvent::CATEGORIES.length)

      holiday_cat = json["available_university_event_categories"].find { |c| c["id"] == "holiday" }
      expect(holiday_cat["name"]).to eq("Holiday")
      expect(holiday_cat["description"]).to include("holidays")

      campus_cat = json["available_university_event_categories"].find { |c| c["id"] == "campus_event" }
      expect(campus_cat["name"]).to eq("Campus Event")
      expect(campus_cat["description"]).to include("Campus activities")
    end
  end
end
