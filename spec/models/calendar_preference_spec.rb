# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: calendar_preferences
#
#  id                   :bigint           not null, primary key
#  description_template :text
#  event_type           :string
#  location_template    :text
#  reminder_settings    :jsonb
#  scope                :integer          not null
#  title_template       :text
#  visibility           :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  color_id             :integer
#  user_id              :bigint           not null
#
# Indexes
#
#  index_calendar_preferences_on_user_id     (user_id)
#  index_calendar_prefs_on_user_scope_type   (user_id,scope,event_type) UNIQUE
#  index_calendar_prefs_one_global_per_user  (user_id) UNIQUE WHERE (scope = 0)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
RSpec.describe CalendarPreference, type: :model do
  let(:user) { User.create!(email: "prefs@wit.edu", password: "password123") }

  before { allow(GoogleCalendarSyncJob).to receive(:perform_later) }

  describe "the university wide scope" do
    it "holds a preference for every university event" do
      preference = user.calendar_preferences.new(scope: :uni_cal_global, reminder_settings: [])

      expect(preference).to be_valid
    end

    it "rejects an event type, because the scope covers them all" do
      preference = user.calendar_preferences.new(scope: :uni_cal_global, event_type: "holiday")

      expect(preference).not_to be_valid
      expect(preference.errors[:event_type]).to be_present
    end

    it "is one row per user" do
      user.calendar_preferences.create!(scope: :uni_cal_global, reminder_settings: [])
      duplicate = user.calendar_preferences.new(scope: :uni_cal_global)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:scope]).to be_present
    end

    it "sits beside the global scope rather than replacing it" do
      user.calendar_preferences.create!(scope: :global, title_template: "{{title}}")
      preference = user.calendar_preferences.new(scope: :uni_cal_global, reminder_settings: [])

      expect(preference).to be_valid
    end
  end

  describe "syncing after a change" do
    it "enqueues a forced sync when the reminders change" do
      preference = user.calendar_preferences.create!(scope: :uni_cal_global, reminder_settings: [])

      preference.update!(reminder_settings: [ { "time" => "1", "type" => "days", "method" => "popup" } ])

      expect(GoogleCalendarSyncJob).to have_received(:perform_later).with(user, force: true)
    end
  end
end
