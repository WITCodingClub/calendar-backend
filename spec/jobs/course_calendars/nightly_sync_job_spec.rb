# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseCalendars::NightlySyncJob do
  def user_with_calendar(**attributes)
    user = create(:user, **attributes)
    create(:course_calendar, oauth_credential: create(:oauth_credential, user: user))
    user
  end

  let!(:first_time) { user_with_calendar(last_calendar_sync_at: nil) }
  let!(:needs_update) { user_with_calendar(calendar_needs_sync: true, last_calendar_sync_at: 1.day.ago) }
  let!(:up_to_date) { user_with_calendar(calendar_needs_sync: false, last_calendar_sync_at: 1.day.ago) }

  it "enqueues a sync job for each user, so the per-user concurrency limit applies" do
    expect { described_class.perform_now }
      .to have_enqueued_job(CourseCalendars::SyncJob)
      .with(first_time, force: false, backfill_historical: true, nightly: true)
      .and have_enqueued_job(CourseCalendars::SyncJob)
      .with(needs_update, force: true, backfill_historical: false, nightly: true)
  end

  it "does not enqueue a sync for a user who is up to date" do
    expect { described_class.perform_now }.to have_enqueued_job(CourseCalendars::SyncJob).exactly(2).times
    expect(CourseCalendars::SyncJob).not_to have_been_enqueued.with(up_to_date, any_args)
  end

  it "does not sync a user inline" do
    allow(CourseCalendars::ScheduleSyncer).to receive(:new)

    described_class.perform_now

    expect(CourseCalendars::ScheduleSyncer).not_to have_received(:new)
  end

  it "puts the nightly syncs behind the syncs that people start" do
    expect { described_class.perform_now }
      .to have_enqueued_job(CourseCalendars::SyncJob).on_queue("low").at_priority(described_class::SYNC_PRIORITY).twice
  end
end
