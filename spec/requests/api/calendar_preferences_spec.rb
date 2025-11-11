# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::CalendarPreferences", type: :request do
  let(:user) { create(:user) }
  let(:jwt_token) { JsonWebTokenService.encode(user_id: user.id) }
  let(:headers) { { "Authorization" => "Bearer #{jwt_token}", "Content-Type" => "application/json" } }

  before do
    # Enable the v1 feature flag for API access
    Flipper.enable(FlipperFlags::V1, user)
    # Stub background job to avoid Solid Queue issues in tests
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
  end

  describe "PUT /api/calendar_preferences/global" do
    context "when updating reminder_settings to empty array" do
      it "allows setting reminder_settings to empty array (no notifications)" do
        put "/api/calendar_preferences/global",
            params: { calendar_preference: { reminder_settings: [] } }.to_json,
            headers: headers

        expect(response).to have_http_status(:ok)

        json = response.parsed_body
        expect(json["reminder_settings"]).to eq([])
      end

      it "allows updating only reminder_settings field with empty array" do
        # First create a preference with some settings
        put "/api/calendar_preferences/global",
            params: {
              calendar_preference: {
                title_template: "{{course_code}}",
                reminder_settings: [{ time: "30", type: "minutes", method: "notification" }]
              }
            }.to_json,
            headers: headers

        expect(response).to have_http_status(:ok)

        # Now update only reminder_settings to empty array
        put "/api/calendar_preferences/global",
            params: { calendar_preference: { reminder_settings: [] } }.to_json,
            headers: headers

        expect(response).to have_http_status(:ok)

        json = response.parsed_body
        expect(json["reminder_settings"]).to eq([])
        expect(json["title_template"]).to eq("{{course_code}}") # Should be preserved
      end
    end

    context "when updating other fields" do
      it "allows setting color_id" do
        put "/api/calendar_preferences/global",
            params: { calendar_preference: { color_id: 5 } }.to_json,
            headers: headers

        expect(response).to have_http_status(:ok)
      end

      it "allows setting multiple fields including empty reminder_settings" do
        put "/api/calendar_preferences/global",
            params: {
              calendar_preference: {
                title_template: "{{course_code}}: {{title}}",
                reminder_settings: [],
                color_id: 3
              }
            }.to_json,
            headers: headers

        expect(response).to have_http_status(:ok)

        json = response.parsed_body
        expect(json["reminder_settings"]).to eq([])
        expect(json["title_template"]).to eq("{{course_code}}: {{title}}")
      end
    end
  end

  describe "PUT /api/calendar_preferences/:event_type" do
    it "allows empty reminder_settings for event type preferences" do
      put "/api/calendar_preferences/lecture",
          params: { calendar_preference: { reminder_settings: [] } }.to_json,
          headers: headers

      expect(response).to have_http_status(:ok)

      json = response.parsed_body
      expect(json["reminder_settings"]).to eq([])
      expect(json["event_type"]).to eq("lecture")
    end
  end
end
