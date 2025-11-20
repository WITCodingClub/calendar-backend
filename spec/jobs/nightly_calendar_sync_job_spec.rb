# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightlyCalendarSyncJob do
  describe "queue assignment" do
    it "is assigned to the low queue" do
      expect(described_class.new.queue_name).to eq("low")
    end
  end

  describe "#perform" do
    let(:user_with_sync_needed) { create(:user, calendar_needs_sync: true) }
    let(:user_never_synced) { create(:user, last_calendar_sync_at: nil) }
    let(:user_up_to_date) { create(:user, calendar_needs_sync: false, last_calendar_sync_at: 1.hour.ago) }
    let(:user_no_calendar) { create(:user, calendar_needs_sync: true) }

    # Create OAuth credentials with course_calendar_id for users who should be synced
    let!(:oauth_with_sync_needed) do
      create(:oauth_credential,
             user: user_with_sync_needed,
             metadata: { "course_calendar_id" => "cal_123" })
    end

    let!(:oauth_never_synced) do
      create(:oauth_credential,
             user: user_never_synced,
             metadata: { "course_calendar_id" => "cal_456" })
    end

    let!(:oauth_up_to_date) do
      create(:oauth_credential,
             user: user_up_to_date,
             metadata: { "course_calendar_id" => "cal_789" })
    end

    # user_no_calendar has no OAuth credential with course_calendar_id

    it "syncs calendars for users who need it" do
      # Stub sync_course_schedule to prevent actual sync
      allow_any_instance_of(User).to receive(:sync_course_schedule)

      described_class.perform_now

      # Verify users were marked as synced
      expect(user_with_sync_needed.reload.calendar_needs_sync).to be false
      expect(user_with_sync_needed.last_calendar_sync_at).to be_present
    end

    it "does not sync calendars for users who are up to date" do
      # Stub sync_course_schedule
      allow_any_instance_of(User).to receive(:sync_course_schedule)

      # Track which users get synced
      synced_user_ids = []
      allow_any_instance_of(User).to receive(:sync_course_schedule) do |user|
        synced_user_ids << user.id
      end

      described_class.perform_now

      # user_up_to_date should not be synced (already up to date)
      expect(synced_user_ids).not_to include(user_up_to_date.id)
    end

    it "does not sync calendars for users without a Google calendar" do
      # Stub sync_course_schedule
      synced_user_ids = []
      allow_any_instance_of(User).to receive(:sync_course_schedule) do |user|
        synced_user_ids << user.id
      end

      described_class.perform_now

      # user_no_calendar should not be synced (no OAuth credential with calendar)
      expect(synced_user_ids).not_to include(user_no_calendar.id)
    end

    it "marks users as synced after successful sync" do
      allow_any_instance_of(User).to receive(:sync_course_schedule)

      described_class.perform_now

      user_with_sync_needed.reload
      expect(user_with_sync_needed.calendar_needs_sync).to be false
      expect(user_with_sync_needed.last_calendar_sync_at).to be_present
    end

    it "continues syncing other users if one fails" do
      # Make one user fail
      allow_any_instance_of(User).to receive(:sync_course_schedule) do |user|
        raise StandardError, "Test error" if user.id == user_with_sync_needed.id
      end

      expect {
        described_class.perform_now
      }.not_to raise_error

      # user_never_synced should still be synced
      expect(user_never_synced.reload.calendar_needs_sync).to be false
    end
  end
end
