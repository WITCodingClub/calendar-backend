# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cleanup::OrphanedCalendarRecordsJob do
  # An access token that expired, and no refresh token to get a new one.
  let(:dead_credential) { create(:oauth_credential, token_expires_at: 1.day.ago, refresh_token: nil) }

  it "deletes a calendar whose credential expired and cannot refresh" do
    calendar = create(:course_calendar, oauth_credential: dead_credential)

    result = described_class.perform_now

    expect(result).to eq(deleted: 1, errors: 0)
    expect(CourseCalendar.exists?(calendar.id)).to be(false)
  end

  it "queues the remote Google calendar deletion for the removed calendar" do
    calendar = create(:course_calendar, oauth_credential: dead_credential)

    expect { described_class.perform_now }
      .to have_enqueued_job(GoogleCalendar::DeleteJob).with(calendar.external_calendar_id)
  end

  it "keeps a calendar whose credential can still refresh" do
    credential = create(:oauth_credential, token_expires_at: 1.day.ago, refresh_token: "synthetic-refresh-token")
    calendar = create(:course_calendar, oauth_credential: credential)

    result = described_class.perform_now

    expect(result).to eq(deleted: 0, errors: 0)
    expect(CourseCalendar.exists?(calendar.id)).to be(true)
  end

  it "keeps a calendar whose token has not expired, even without a refresh token" do
    credential = create(:oauth_credential, token_expires_at: 1.day.from_now, refresh_token: nil)
    calendar = create(:course_calendar, oauth_credential: credential)

    described_class.perform_now

    expect(CourseCalendar.exists?(calendar.id)).to be(true)
  end

  it "returns zero counts when no calendar is orphaned" do
    expect(described_class.perform_now).to eq(deleted: 0, errors: 0)
  end

  it "reports an error, counts it, and goes on to the next calendar" do
    broken = create(:course_calendar, oauth_credential: dead_credential)
    fine = create(:course_calendar, oauth_credential: create(:oauth_credential, token_expires_at: 2.days.ago, refresh_token: nil))
    allow(Rails.error).to receive(:report)
    allow_any_instance_of(CourseCalendar).to receive(:destroy!).and_wrap_original do |original, *args|
      raise ActiveRecord::RecordNotDestroyed, "synthetic failure" if original.receiver.id == broken.id

      original.call(*args)
    end

    result = described_class.perform_now

    expect(result).to eq(deleted: 1, errors: 1)
    expect(CourseCalendar.exists?(broken.id)).to be(true)
    expect(CourseCalendar.exists?(fine.id)).to be(false)
    expect(Rails.error).to have_received(:report)
      .with(an_instance_of(ActiveRecord::RecordNotDestroyed), handled: true, context: { course_calendar_id: broken.id })
  end

  describe "#determine_orphan_reason" do
    subject(:job) { described_class.new }

    it "names an expired token without a refresh token" do
      calendar = create(:course_calendar, oauth_credential: dead_credential)

      expect(job.send(:determine_orphan_reason, calendar)).to eq("Expired token without refresh capability")
    end

    it "names a missing credential" do
      expect(job.send(:determine_orphan_reason, build(:course_calendar, oauth_credential: nil)))
        .to eq("Missing OAuth credential")
    end

    it "names a credential whose user is gone" do
      calendar = create(:course_calendar)
      calendar.oauth_credential.user_id = 0

      expect(job.send(:determine_orphan_reason, calendar)).to eq("Missing user")
    end

    it "falls back to an unknown reason" do
      calendar = create(:course_calendar, oauth_credential: create(:oauth_credential, :microsoft))

      expect(job.send(:determine_orphan_reason, calendar)).to eq("Unknown reason")
    end
  end
end
