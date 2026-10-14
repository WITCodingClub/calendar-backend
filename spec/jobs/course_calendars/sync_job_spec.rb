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

  it "does not record the sync on a run that a person started" do
    described_class.perform_now(user)

    expect(user.reload).to have_attributes(calendar_needs_sync: true, last_calendar_sync_at: nil)
  end

  it "uses one lock key for each user, with or without the nightly arguments" do
    plain   = described_class.new(user, force: true)
    nightly = described_class.new(user, force: false, backfill_historical: true, nightly: true)

    expect(nightly.concurrency_key).to eq(plain.concurrency_key)
  end
end
