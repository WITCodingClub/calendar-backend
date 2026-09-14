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

  describe "associations and validations" do
    subject { create(:calendar_preference) }

    it { is_expected.to belong_to(:user) }

    it { is_expected.to validate_presence_of(:scope) }

    # validate_uniqueness_of probes case sensitivity by upcasing the value it
    # assigns (e.g. "global" -> "GLOBAL"), but :scope is enum-backed, so
    # anything other than one of its declared labels raises ArgumentError
    # instead of failing validation. Covered instead by the "is one row per
    # user" example below, which exercises the real uniqueness scope.

    it { is_expected.to validate_length_of(:title_template).is_at_most(500).allow_blank }
    it { is_expected.to validate_length_of(:description_template).is_at_most(2000).allow_blank }
    it { is_expected.to validate_length_of(:location_template).is_at_most(500).allow_blank }
    it { is_expected.to validate_inclusion_of(:color_id).in_range(1..11).allow_nil }
    it { is_expected.to validate_inclusion_of(:visibility).in_array(%w[public private default]).allow_blank }

    it do
      expect(subject).to define_enum_for(:scope)
        .with_values(global: 0, event_type: 1, uni_cal_category: 2, uni_cal_global: 3)
        .with_prefix
        .backed_by_column_of_type(:integer)
    end

    # #event_type's presence/absence depends on which scope is set
    # (scope_event_type?/scope_uni_cal_category? require it, scope_global?/
    # scope_uni_cal_global? forbid it), so there's no single unconditional
    # validate_presence_of/validate_absence_of to assert here.
  end

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
