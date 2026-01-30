# frozen_string_literal: true

# == Schema Information
#
# Table name: user_extension_configs
# Database name: primary
#
#  id                          :bigint           not null, primary key
#  advanced_editing            :boolean          default(FALSE), not null
#  default_color_lab           :string           default("#f6bf26"), not null
#  default_color_lecture       :string           default("#039be5"), not null
#  military_time               :boolean          default(FALSE), not null
#  sync_university_events      :boolean          default(FALSE), not null
#  university_event_categories :jsonb
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  user_id                     :bigint           not null
#
# Indexes
#
#  index_user_extension_configs_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
require "rails_helper"

RSpec.describe UserExtensionConfig do
  let(:user) { create(:user) }
  let(:config) { user.user_extension_config }

  describe "associations" do
    it "belongs to a user" do
      expect(config.user).to eq(user)
    end
  end

  describe "callbacks" do
    describe "#sync_calendar_if_colors_changed" do
      before do
        # Stub the job to avoid actual job execution
        allow(GoogleCalendarSyncJob).to receive(:perform_later)
      end

      it "queues a sync job when default_color_lecture changes" do
        config.update!(default_color_lecture: "#ff0000")
        expect(GoogleCalendarSyncJob).to have_received(:perform_later).with(user, force: true)
      end

      it "queues a sync job when default_color_lab changes" do
        config.update!(default_color_lab: "#00ff00")
        expect(GoogleCalendarSyncJob).to have_received(:perform_later).with(user, force: true)
      end

      it "queues a sync job when both colors change" do
        config.update!(
          default_color_lecture: "#ff0000",
          default_color_lab: "#00ff00"
        )
        expect(GoogleCalendarSyncJob).to have_received(:perform_later).with(user, force: true).once
      end

      it "does not queue a sync job when military_time changes" do
        config.update!(military_time: true)
        expect(GoogleCalendarSyncJob).not_to have_received(:perform_later)
      end

      it "does not queue a sync job when colors don't change" do
        config.update!(default_color_lecture: config.default_color_lecture)
        expect(GoogleCalendarSyncJob).not_to have_received(:perform_later)
      end

      it "queues a sync job when sync_university_events changes" do
        config.update!(sync_university_events: true)
        expect(GoogleCalendarSyncJob).to have_received(:perform_later).with(user, force: true)
      end

      it "queues a sync job when university_event_categories changes" do
        config.update!(
          sync_university_events: true,
          university_event_categories: ["campus_event", "academic"]
        )
        expect(GoogleCalendarSyncJob).to have_received(:perform_later).with(user, force: true)
      end
    end
  end

  describe "university event settings" do
    describe "#clear_categories_when_sync_disabled" do
      it "clears university_event_categories when sync_university_events is set to false" do
        # First enable sync and set categories
        config.update!(
          sync_university_events: true,
          university_event_categories: ["campus_event", "academic", "deadline"]
        )

        expect(config.university_event_categories).to contain_exactly("campus_event", "academic", "deadline")

        # Now disable sync - categories should be cleared
        config.update!(sync_university_events: false)

        expect(config.reload.university_event_categories).to eq([])
      end

      it "does not clear categories when sync_university_events is already false" do
        # Start with sync disabled and empty categories
        expect(config.sync_university_events).to be false
        initial_categories = config.university_event_categories

        # Update another field
        config.update!(military_time: true)

        # Categories should remain unchanged
        expect(config.university_event_categories).to eq(initial_categories)
      end

      it "does not clear categories when sync_university_events is set to true" do
        # Start with sync disabled
        config.update!(sync_university_events: false, university_event_categories: [])

        # Enable sync and set categories
        config.update!(
          sync_university_events: true,
          university_event_categories: ["campus_event"]
        )

        # Categories should be set
        expect(config.reload.university_event_categories).to eq(["campus_event"])
      end

      it "clears categories in a single update when toggling sync off" do
        # Enable sync with categories in one go
        config.update!(
          sync_university_events: true,
          university_event_categories: ["campus_event", "academic"]
        )

        # Now try to disable sync and set categories at the same time
        # The callback should clear categories even if they're set in the same update
        config.update!(
          sync_university_events: false,
          university_event_categories: ["deadline"]
        )

        # Categories should be cleared (callback runs before save)
        expect(config.reload.university_event_categories).to eq([])
      end
    end

    describe "integration with calendar sync" do
      it "triggers sync with cleared categories when toggle is disabled" do
        # First, enable sync with multiple categories
        expect(GoogleCalendarSyncJob).to receive(:perform_later).with(user, force: true)

        config.update!(
          sync_university_events: true,
          university_event_categories: ["campus_event", "academic", "deadline", "finals"]
        )

        # Now disable sync - this should clear categories AND trigger sync
        expect(GoogleCalendarSyncJob).to receive(:perform_later).with(user, force: true)

        config.update!(sync_university_events: false)

        # Verify categories are cleared
        expect(config.reload.university_event_categories).to eq([])
        expect(config.sync_university_events).to be false
      end

      it "ensures non-holiday events are excluded after disabling sync" do
        allow(GoogleCalendarSyncJob).to receive(:perform_later)

        # Setup: user has sync enabled with categories
        config.update!(
          sync_university_events: true,
          university_event_categories: ["campus_event", "academic"]
        )

        # When sync is enabled, build_university_events_for_sync should include these categories
        user_events = user.send(:build_university_events_for_sync)
        event_ids = user_events.map { |e| e[:university_calendar_event_id] }.compact # rubocop:disable Rails/Pluck

        # Disable sync
        config.update!(sync_university_events: false)

        # After disabling, build_university_events_for_sync should only include holidays
        user_events_after = user.send(:build_university_events_for_sync)
        holiday_events = UniversityCalendarEvent.holidays.upcoming.pluck(:id)

        # All events should be holidays
        event_ids_after = user_events_after.map { |e| e[:university_calendar_event_id] }.compact # rubocop:disable Rails/Pluck
        expect(event_ids_after - holiday_events).to be_empty
      end
    end
  end
end
