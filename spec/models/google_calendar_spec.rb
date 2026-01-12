# frozen_string_literal: true

# == Schema Information
#
# Table name: google_calendars
# Database name: primary
#
#  id                  :bigint           not null, primary key
#  description         :text
#  last_synced_at      :datetime
#  summary             :string
#  time_zone           :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  google_calendar_id  :string           not null
#  oauth_credential_id :bigint           not null
#
# Indexes
#
#  index_google_calendars_on_google_calendar_id   (google_calendar_id) UNIQUE
#  index_google_calendars_on_last_synced_at       (last_synced_at)
#  index_google_calendars_on_oauth_credential_id  (oauth_credential_id)
#
# Foreign Keys
#
#  fk_rails_...  (oauth_credential_id => oauth_credentials.id)
#
require "rails_helper"

RSpec.describe GoogleCalendar do
  describe "validations" do
    it "validates uniqueness of google_calendar_id" do
      create(:google_calendar, google_calendar_id: "unique_cal_123")
      duplicate = build(:google_calendar, google_calendar_id: "unique_cal_123")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:google_calendar_id]).to be_present
    end
  end

  describe "scopes" do
    let(:user) { create(:user) }
    let(:other_user) { create(:user) }
    let!(:user_calendar) { create(:google_calendar, oauth_credential: create(:oauth_credential, user: user)) }
    let!(:other_calendar) { create(:google_calendar, oauth_credential: create(:oauth_credential, user: other_user)) }

    describe ".for_user" do
      it "returns calendars for the specified user" do
        expect(described_class.for_user(user)).to include(user_calendar)
        expect(described_class.for_user(user)).not_to include(other_calendar)
      end
    end

    describe ".stale" do
      let!(:fresh_calendar) { create(:google_calendar, last_synced_at: 30.minutes.ago) }
      let!(:stale_calendar) { create(:google_calendar, :stale) }
      let!(:never_synced) { create(:google_calendar, :never_synced) }

      it "returns calendars that haven't been synced in over an hour" do
        results = described_class.stale
        expect(results).to include(stale_calendar, never_synced)
        expect(results).not_to include(fresh_calendar)
      end

      it "accepts custom staleness threshold" do
        results = described_class.stale(15.minutes)
        expect(results).to include(fresh_calendar, stale_calendar, never_synced)
      end
    end
  end

  describe "#mark_synced!" do
    let(:calendar) { create(:google_calendar, :never_synced) }

    it "updates last_synced_at to current time" do
      calendar.mark_synced!
      expect(calendar.reload.last_synced_at).to be_within(1.second).of(Time.current)
    end
  end

  describe "#needs_sync?" do
    it "returns true when never synced" do
      calendar = create(:google_calendar, :never_synced)
      expect(calendar.needs_sync?).to be true
    end

    it "returns true when synced over an hour ago" do
      calendar = create(:google_calendar, last_synced_at: 2.hours.ago)
      expect(calendar.needs_sync?).to be true
    end

    it "returns false when recently synced" do
      calendar = create(:google_calendar, last_synced_at: 30.minutes.ago)
      expect(calendar.needs_sync?).to be false
    end

    it "accepts custom threshold" do
      calendar = create(:google_calendar, last_synced_at: 10.minutes.ago)
      expect(calendar.needs_sync?(5.minutes)).to be true
      expect(calendar.needs_sync?(15.minutes)).to be false
    end
  end

  describe "before_destroy callback", :job do
    let(:calendar) { create(:google_calendar, google_calendar_id: "test_cal_123") }

    describe "#enqueue_google_calendar_deletion" do
      it "enqueues GoogleCalendarDeleteJob when calendar is destroyed" do
        ActiveJob::Base.queue_adapter = :test

        expect {
          calendar.destroy
        }.to have_enqueued_job(GoogleCalendarDeleteJob).with("test_cal_123")
      end

      it "logs successful job enqueue" do
        allow(Rails.logger).to receive(:info)

        calendar.destroy

        expect(Rails.logger).to have_received(:info).with(/Enqueued GoogleCalendarDeleteJob for calendar test_cal_123/)
      end
    end

    describe "cascade deletion from user" do
      let(:user) { create(:user) }
      let(:oauth_credential) { create(:oauth_credential, user: user) }
      let!(:google_calendar) { create(:google_calendar, oauth_credential: oauth_credential) }

      it "enqueues deletion job when user is destroyed" do
        ActiveJob::Base.queue_adapter = :test
        calendar_id = google_calendar.google_calendar_id

        expect {
          user.destroy
        }.to have_enqueued_job(GoogleCalendarDeleteJob).with(calendar_id)
      end

      it "removes calendar from database when user is destroyed" do
        expect {
          user.destroy
        }.to change(described_class, :count).by(-1)
      end
    end

    describe "cascade deletion from oauth_credential" do
      let(:oauth_credential) { create(:oauth_credential) }
      let!(:google_calendar) { create(:google_calendar, oauth_credential: oauth_credential) }

      it "enqueues deletion job when oauth_credential is destroyed" do
        ActiveJob::Base.queue_adapter = :test
        calendar_id = google_calendar.google_calendar_id

        expect {
          oauth_credential.destroy
        }.to have_enqueued_job(GoogleCalendarDeleteJob).with(calendar_id)
      end

      it "removes calendar from database when oauth_credential is destroyed" do
        expect {
          oauth_credential.destroy
        }.to change(described_class, :count).by(-1)
      end
    end
  end
end
