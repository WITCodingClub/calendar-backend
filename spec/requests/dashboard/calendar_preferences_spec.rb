# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::CalendarPreferences", type: :request do
  let(:user) do
    User.create!(email: "dash@wit.edu", password: "password123", confirmed_at: Time.current)
  end
  let(:config) { user.user_extension_config.reload }

  before do
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
    sign_in user
  end

  describe "GET /dashboard/calendar_preferences" do
    it "shows the university event sync toggle and every category except holidays" do
      get dashboard_calendar_preferences_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="sync_university_events"')
      expect(response.body).to include('value="finals"')
      expect(response.body).not_to include('value="holiday"')
    end

    it "does not show categories that no longer sync" do
      get dashboard_calendar_preferences_path

      expect(response.body).not_to include('value="campus_event"', 'value="meeting"', 'value="announcement"')
    end

    it "checks the categories the user already picked" do
      user.user_extension_config.update!(sync_university_events: true, university_event_categories: [ "finals" ])

      get dashboard_calendar_preferences_path

      expect(response.body).to match(/<input[^>]*value="finals"[^>]*checked/)
      expect(response.body).not_to match(/<input[^>]*value="deadline"[^>]*checked/)
    end
  end

  describe "PATCH /dashboard/calendar_preferences/university_events" do
    it "turns on sync for the chosen categories and queues a sync" do
      patch university_events_dashboard_calendar_preferences_path,
            params: { sync_university_events: "1", university_event_categories: %w[finals deadline] }

      expect(response).to redirect_to(dashboard_calendar_preferences_path)
      expect(config.sync_university_events).to be(true)
      expect(config.university_event_categories).to contain_exactly("finals", "deadline")
      expect(GoogleCalendarSyncJob).to have_received(:perform_later).with(user, force: true)
    end

    it "turns off sync but keeps the chosen categories" do
      user.user_extension_config.update!(sync_university_events: true, university_event_categories: [ "finals" ])

      patch university_events_dashboard_calendar_preferences_path,
            params: { sync_university_events: "0", university_event_categories: [ "finals" ] }

      expect(config.sync_university_events).to be(false)
      expect(config.university_event_categories).to eq([ "finals" ])
    end

    it "clears the categories when none are checked" do
      user.user_extension_config.update!(sync_university_events: true, university_event_categories: [ "finals" ])

      patch university_events_dashboard_calendar_preferences_path,
            params: { sync_university_events: "1", university_event_categories: [ "" ] }

      expect(config.university_event_categories).to eq([])
    end

    it "drops categories that do not exist" do
      patch university_events_dashboard_calendar_preferences_path,
            params: { sync_university_events: "1", university_event_categories: %w[finals parties] }

      expect(config.university_event_categories).to eq([ "finals" ])
    end

    it "drops categories that no longer sync" do
      patch university_events_dashboard_calendar_preferences_path,
            params: { sync_university_events: "1", university_event_categories: %w[finals campus_event] }

      expect(config.university_event_categories).to eq([ "finals" ])
    end

    it "does not queue a sync when nothing changed" do
      user.user_extension_config.update_columns(sync_university_events: false, university_event_categories: [])

      patch university_events_dashboard_calendar_preferences_path,
            params: { sync_university_events: "0", university_event_categories: [ "" ] }

      expect(GoogleCalendarSyncJob).not_to have_received(:perform_later)
    end
  end
end
