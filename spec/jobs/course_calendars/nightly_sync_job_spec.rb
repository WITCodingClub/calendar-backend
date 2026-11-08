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
      .with(needs_update, force: false, backfill_historical: false, nightly: true)
  end

  it "does not force any sync, so only changed events reach the provider" do
    expect { described_class.perform_now }
      .not_to have_enqueued_job(CourseCalendars::SyncJob).with(anything, hash_including(force: true))
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
      .to have_enqueued_job(CourseCalendars::SyncJob).on_queue("default").at_priority(CourseCalendars::SyncJob::BULK_PRIORITY).twice
  end
  it "puts the run in one batch that reports its totals" do
    previous = CourseCalendars::SyncJob.queue_adapter
    CourseCalendars::SyncJob.queue_adapter = :solid_queue

    described_class.perform_now

    batch = SolidQueue::Batch.sole
    expect(batch.metadata[:reason]).to eq("nightly")
    expect(batch.jobs.count).to eq(2)
    expect(batch.on_finish["job_class"]).to eq("CourseCalendars::BulkSyncFinishedJob")
  ensure
    CourseCalendars::SyncJob.queue_adapter = previous
  end
end
