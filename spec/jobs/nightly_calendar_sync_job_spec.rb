require 'rails_helper'

RSpec.describe NightlyCalendarSyncJob, type: :job do
  describe '#perform' do
    let!(:user_with_sync_needed) { create(:user, calendar_needs_sync: true, google_course_calendar_id: 'cal_123') }
    let!(:user_never_synced) { create(:user, last_calendar_sync_at: nil, google_course_calendar_id: 'cal_456') }
    let!(:user_up_to_date) { create(:user, calendar_needs_sync: false, last_calendar_sync_at: 1.hour.ago, google_course_calendar_id: 'cal_789') }
    let!(:user_no_calendar) { create(:user, calendar_needs_sync: true, google_course_calendar_id: nil) }

    before do
      allow_any_instance_of(User).to receive(:sync_course_schedule)
    end

    it 'syncs calendars for users who need it' do
      described_class.perform_now

      expect(user_with_sync_needed).to have_received(:sync_course_schedule)
      expect(user_never_synced).to have_received(:sync_course_schedule)
    end

    it 'does not sync calendars for users who are up to date' do
      described_class.perform_now

      expect(user_up_to_date).not_to have_received(:sync_course_schedule)
    end

    it 'does not sync calendars for users without a Google calendar' do
      described_class.perform_now

      expect(user_no_calendar).not_to have_received(:sync_course_schedule)
    end

    it 'marks users as synced after successful sync' do
      described_class.perform_now

      user_with_sync_needed.reload
      expect(user_with_sync_needed.calendar_needs_sync).to be false
      expect(user_with_sync_needed.last_calendar_sync_at).to be_present
    end

    it 'continues syncing other users if one fails' do
      allow(user_with_sync_needed).to receive(:sync_course_schedule).and_raise(StandardError.new("Test error"))

      expect {
        described_class.perform_now
      }.not_to raise_error

      expect(user_never_synced).to have_received(:sync_course_schedule)
    end
  end
end
