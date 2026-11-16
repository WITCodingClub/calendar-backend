# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: event_preferences
#
#  id                   :bigint           not null, primary key
#  description_template :text
#  location_template    :text
#  preferenceable_type  :string           not null
#  reminder_settings    :jsonb
#  title_template       :text
#  visibility           :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  color_id             :string
#  preferenceable_id    :bigint           not null
#  user_id              :bigint           not null
#
# Indexes
#
#  index_event_preferences_on_preferenceable     (preferenceable_type,preferenceable_id)
#  index_event_prefs_on_user_and_preferenceable  (user_id,preferenceable_type,preferenceable_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
RSpec.describe EventPreference, type: :model do
  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:preferenceable) }

  it { is_expected.to validate_length_of(:title_template).is_at_most(500).allow_blank }
  it { is_expected.to validate_length_of(:description_template).is_at_most(2000).allow_blank }
  it { is_expected.to validate_length_of(:location_template).is_at_most(500).allow_blank }
  it { is_expected.to allow_values("#1a2b3c", "#d50000", nil).for(:color_id) }
  it { is_expected.not_to allow_values("red", "#12345", "#gggggg", "12").for(:color_id) }
  it { is_expected.to normalize(:color_id).from("#1A2B3C").to("#1a2b3c") }
  it { is_expected.to normalize(:color_id).from(11).to("#d50000") }
  it { is_expected.to normalize(:color_id).from("").to(nil) }
  it { is_expected.to validate_inclusion_of(:visibility).in_array(%w[public private default]).allow_blank }

  # #at_least_one_preference_set is a custom, cross-field validation (title,
  # description, location, reminder_settings, color_id, and visibility can
  # satisfy each other), so there's no single attribute for
  # validate_presence_of to point at.

  describe "syncing after a change" do
    let(:user)        { create(:user, :with_calendar) }
    let!(:preference) { create(:event_preference, user: user, color_id: "#1a2b3c") }

    it "enqueues one forced sync when a field changes, and when the row goes" do
      expect { preference.update!(color_id: "#d50000") }
        .to have_enqueued_job(CourseCalendars::SyncJob).with(user, force: true).exactly(:once)
      expect { preference.destroy! }.to have_enqueued_job(CourseCalendars::SyncJob).with(user, force: true).exactly(:once)
    end

    it "enqueues nothing for a save that changes no field" do
      expect { preference.update!(color_id: "#1a2b3c") }.not_to have_enqueued_job(CourseCalendars::SyncJob)
    end

    it "enqueues nothing when its meeting time is destroyed and takes it along" do
      expect { preference.preferenceable.destroy! }.not_to have_enqueued_job(CourseCalendars::SyncJob)
      expect(EventPreference.exists?(preference.id)).to be(false)
    end

    it "enqueues nothing when the sync deletes its calendar event and takes it along" do
      calendar = user.course_calendars.sole
      row      = create(:calendar_event, course_calendar: calendar, external_event_id: "evt-1")
      create(:event_preference, :for_calendar_event, user: user, preferenceable: row, color_id: "#1a2b3c")
      service = GoogleCalendar::Provider.new(user)
      allow(service).to receive(:delete_event)

      expect { service.send(:delete_rows, [ row ]) }.not_to have_enqueued_job(CourseCalendars::SyncJob)
      expect(EventPreference.where(preferenceable: row)).to be_empty
    end

    it "enqueues nothing when the orphan cleanup deletes its calendar event" do
      row = create(:calendar_event, course_calendar: user.course_calendars.sole)
      create(:event_preference, :for_calendar_event, user: user, preferenceable: row, color_id: "#1a2b3c")
      row.update_columns(meeting_time_id: nil) # rubocop:disable Rails/SkipsModelValidations

      expect { Cleanup::OrphanedCalendarEventsJob.perform_now }.not_to have_enqueued_job(CourseCalendars::SyncJob)
      expect(EventPreference.where(preferenceable: row)).to be_empty
    end
  end
end
