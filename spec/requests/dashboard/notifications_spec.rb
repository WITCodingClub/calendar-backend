# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Notifications", type: :request do
  let(:user) do
    User.create!(email: "dash@wit.edu", password: "password123", confirmed_at: Time.current)
  end

  def university_preference = user.calendar_preferences.find_by(scope: :uni_cal_global)

  before do
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
    sign_in user
  end

  describe "PATCH /dashboard/notifications/university_events" do
    it "turns off the reminders of university events" do
      patch university_events_dashboard_notifications_path, params: { mode: "off" }

      expect(response).to redirect_to(dashboard_notifications_path)
      expect(university_preference.reminder_settings).to eq([])
      expect(GoogleCalendarSyncJob).to have_received(:perform_later).with(user, force: true)
    end

    it "stores a custom reminder" do
      patch university_events_dashboard_notifications_path,
            params: { mode: "custom", reminder: "2:days", delivery: "email" }

      expect(university_preference.reminder_settings).to eq(
        [ { "time" => "2", "type" => "days", "method" => "email" } ]
      )
    end

    it "returns to the default by clearing the stored reminders" do
      user.calendar_preferences.create!(scope: :uni_cal_global, reminder_settings: [])

      patch university_events_dashboard_notifications_path, params: { mode: "default" }

      expect(university_preference.reminder_settings).to be_nil
    end

    it "rejects a reminder that is not on the list" do
      patch university_events_dashboard_notifications_path,
            params: { mode: "custom", reminder: "3:centuries" }

      expect(flash[:alert]).to eq("Pick a reminder time.")
      expect(university_preference).to be_nil
    end

    it "leaves the class reminders untouched" do
      global = user.calendar_preferences.create!(
        scope: :global, reminder_settings: [ { "time" => "10", "type" => "minutes", "method" => "popup" } ]
      )

      patch university_events_dashboard_notifications_path, params: { mode: "off" }

      expect(global.reload.reminder_settings).to eq(
        [ { "time" => "10", "type" => "minutes", "method" => "popup" } ]
      )
    end
  end
end
