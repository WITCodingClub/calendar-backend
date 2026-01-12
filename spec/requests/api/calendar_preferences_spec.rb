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

  describe "PUT /api/calendar_preferences/uni_cal:category" do
    it "allows setting color_id for university calendar category" do
      put "/api/calendar_preferences/uni_cal:holiday",
          params: { calendar_preference: { color_id: 8 } }.to_json,
          headers: headers

      expect(response).to have_http_status(:ok)

      json = response.parsed_body
      expect(json["event_type"]).to eq("holiday")
      expect(json["scope"]).to eq("uni_cal_category")
    end

    it "allows setting multiple fields for uni cal category" do
      put "/api/calendar_preferences/uni_cal:deadline",
          params: {
            calendar_preference: {
              color_id: 11,
              title_template: "{{summary}}",
              reminder_settings: [{ time: "1", type: "days", method: "popup" }]
            }
          }.to_json,
          headers: headers

      expect(response).to have_http_status(:ok)

      json = response.parsed_body
      expect(json["scope"]).to eq("uni_cal_category")
      expect(json["event_type"]).to eq("deadline")
      expect(json["title_template"]).to eq("{{summary}}")
    end

    it "allows empty reminder_settings for uni cal category" do
      put "/api/calendar_preferences/uni_cal:term_dates",
          params: { calendar_preference: { reminder_settings: [] } }.to_json,
          headers: headers

      expect(response).to have_http_status(:ok)

      json = response.parsed_body
      expect(json["reminder_settings"]).to eq([])
    end
  end

  describe "GET /api/calendar_preferences/uni_cal:category" do
    before do
      user.calendar_preferences.create!(
        scope: :uni_cal_category,
        event_type: "holiday",
        color_id: 5
      )
    end

    it "returns the uni cal category preference" do
      get "/api/calendar_preferences/uni_cal:holiday", headers: headers

      expect(response).to have_http_status(:ok)

      json = response.parsed_body
      expect(json["scope"]).to eq("uni_cal_category")
      expect(json["event_type"]).to eq("holiday")
    end
  end

  describe "DELETE /api/calendar_preferences/uni_cal:category" do
    before do
      user.calendar_preferences.create!(
        scope: :uni_cal_category,
        event_type: "holiday",
        color_id: 5
      )
    end

    it "deletes the uni cal category preference" do
      expect {
        delete "/api/calendar_preferences/uni_cal:holiday", headers: headers
      }.to change { user.calendar_preferences.count }.by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end

  describe "GET /api/calendar_preferences (index)" do
    before do
      user.calendar_preferences.create!(scope: :global, color_id: 3)
      user.calendar_preferences.create!(scope: :event_type, event_type: "lecture", color_id: 5)
      user.calendar_preferences.create!(scope: :uni_cal_category, event_type: "holiday", color_id: 8)
      user.calendar_preferences.create!(scope: :uni_cal_category, event_type: "deadline", color_id: 11)
    end

    it "returns all preference types including uni_cal_categories" do
      get "/api/calendar_preferences", headers: headers

      expect(response).to have_http_status(:ok)

      json = response.parsed_body
      expect(json["global"]).to be_present
      expect(json["event_types"]).to be_present
      expect(json["event_types"]["lecture"]).to be_present
      expect(json["uni_cal_categories"]).to be_present
      expect(json["uni_cal_categories"]["holiday"]).to be_present
      expect(json["uni_cal_categories"]["deadline"]).to be_present
    end
  end
end
