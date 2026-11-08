# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseCalendars::SyncJob do
  let(:user) { create(:user, calendar_needs_sync: true, last_calendar_sync_at: nil) }

  before { allow(user).to receive(:sync_course_schedule) }

  it "syncs the schedule, with the backfill on a forced sync" do
    described_class.perform_now(user, force: true)

    expect(user).to have_received(:sync_course_schedule).with(force: true, backfill_historical: true)
  end

  it "passes the backfill choice of the nightly run" do
    described_class.perform_now(user, force: false, backfill_historical: true, nightly: true)

    expect(user).to have_received(:sync_course_schedule).with(force: false, backfill_historical: true)
  end

  # ScheduleSyncer records a sync only when it changed something. The nightly
  # run records every sync, so a user with no events is not picked again.
  it "records the sync on a nightly run, also when nothing changed" do
    described_class.perform_now(user, nightly: true)

    expect(user.reload).to have_attributes(calendar_needs_sync: false, last_calendar_sync_at: be_present)
  end

  describe ".perform_bulk_later" do
    it "queues the sync on default, behind the other default jobs" do
      expect { described_class.perform_bulk_later(user, force: true) }
        .to have_enqueued_job(described_class).with(user, force: true).on_queue("default").at_priority(described_class::BULK_PRIORITY)
    end
  end

  it "does not record the sync on a run that a person started" do
    described_class.perform_now(user)

    expect(user.reload).to have_attributes(calendar_needs_sync: true, last_calendar_sync_at: nil)
  end

  it "uses one lock key for each user, with or without the nightly arguments" do
    plain   = described_class.new(user, force: true)
    nightly = described_class.new(user, force: false, backfill_historical: true, nightly: true)

    expect(nightly.concurrency_key).to eq(plain.concurrency_key)
  end
  describe ".perform_bulk_in_batch" do
    let(:users) { create_list(:user, 2) }

    it "queues a bulk sync for each user in one batch, which waits for them" do
      previous = described_class.queue_adapter
      described_class.queue_adapter = :solid_queue

      batch = described_class.perform_bulk_in_batch(User.where(id: users.map(&:id)).order(id: :desc), reason: "finals", force: true)

      expect(batch.metadata[:reason]).to eq("finals")
      expect(batch.description).to eq("Calendar sync: finals")
      expect(batch.jobs.pluck(:queue_name, :priority).uniq).to eq([ [ "default", described_class::BULK_PRIORITY ] ])
      expect(batch.jobs.order(:id).map { |job| GlobalID::Locator.locate(job.arguments["arguments"].first["_aj_globalid"]).id })
        .to eq(users.map(&:id).sort)
      expect(SolidQueue::Job.where(class_name: "CourseCalendars::BulkSyncFinishedJob")).to be_empty
    ensure
      described_class.queue_adapter = previous
    end

    it "reports the totals when the batch finishes" do
      described_class.perform_bulk_in_batch(User.where(id: users.map(&:id)), reason: "finals")

      # The :test adapter puts no job in the batch, so it finishes at once.
      expect(SolidQueue::Job.where(class_name: "CourseCalendars::BulkSyncFinishedJob").count).to eq(1)
    end
  end
end
