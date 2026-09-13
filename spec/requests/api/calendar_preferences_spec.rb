# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::CalendarPreferences", type: :request do
  let(:user) { User.create!(email: "api-prefs@wit.edu", password: "password123", confirmed_at: Time.current) }
  let(:headers) { { "Authorization" => "Bearer #{api_token_for(user)}" } }

  def json = JSON.parse(response.body)
  def university_preference = user.calendar_preferences.find_by(scope: :uni_cal_global)

  before do
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
    Flipper.enable(FlipperFlags::V1)
  end

  after { Flipper.disable(FlipperFlags::V1) }

  describe "PATCH /api/calendar_preferences/uni_cal" do
    it "sets one reminder for every university event" do
      patch "/api/calendar_preferences/uni_cal",
            params: {
              calendar_preference: {
                reminder_settings: [ { time: "15", type: "hours", method: "notification" } ]
              }
            },
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(json["scope"]).to eq("uni_cal_global")
      expect(university_preference.reminder_settings).to eq(
        [ { "time" => "15", "type" => "hours", "method" => "popup" } ]
      )
    end

    it "turns the reminders off with an empty list" do
      patch "/api/calendar_preferences/uni_cal",
            params: { calendar_preference: { reminder_settings: [] } },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(university_preference.reminder_settings).to eq([])
    end

    it "turns the reminders off from a form, which sends an empty list as a blank entry" do
      patch "/api/calendar_preferences/uni_cal",
            params: { calendar_preference: { reminder_settings: [ "" ] } },
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(university_preference.reminder_settings).to eq([])
    end

    it "returns to the system default when the list is 'default'" do
      user.calendar_preferences.create!(scope: :uni_cal_global, reminder_settings: [])

      patch "/api/calendar_preferences/uni_cal",
            params: { calendar_preference: { reminder_settings: "default" } },
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(university_preference.reminder_settings).to be_nil
    end

    it "keeps the category scope separate from the university wide scope" do
      patch "/api/calendar_preferences/uni_cal:holiday",
            params: { calendar_preference: { reminder_settings: [] } },
            headers: headers

      expect(json["scope"]).to eq("uni_cal_category")
      expect(json["event_type"]).to eq("holiday")
      expect(university_preference).to be_nil
    end
  end

  describe "GET /api/calendar_preferences" do
    it "publishes the university wide preference beside the global one" do
      user.calendar_preferences.create!(scope: :uni_cal_global, reminder_settings: [])

      get "/api/calendar_preferences", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json["uni_cal_global"]["reminder_settings"]).to eq([])
      expect(json["global"]).to be_nil
    end

    it "reports no university wide preference until one is set" do
      get "/api/calendar_preferences", headers: headers

      expect(json["uni_cal_global"]).to be_nil
    end
  end
end
