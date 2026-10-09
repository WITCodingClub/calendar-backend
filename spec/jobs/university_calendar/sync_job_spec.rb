# frozen_string_literal: true

require "rails_helper"

RSpec.describe UniversityCalendar::SyncJob do
  let(:no_changes) { { created: 0, updated: 0, cancelled: 0, changed_categories: [] } }
  let(:import_result) { no_changes }

  # A person with a course calendar, so a sync can be queued for them.
  def user_with_calendar(sync_university_events:)
    user = create(:user)
    user.user_extension_config.update!(sync_university_events: sync_university_events)
    create(:course_calendar, oauth_credential: create(:oauth_credential, user: user))
    user
  end

  # The ids of the users that got a forced calendar sync while the block ran.
  def synced_user_ids
    queue = ActiveJob::Base.queue_adapter.enqueued_jobs
    before = queue.size
    yield
    queue.drop(before)
                 .select { |job| job[:job] == CourseCalendars::SyncJob }
                 .map { |job| job[:args].first["_aj_globalid"].split("/").last.to_i }
  end

  before do
    allow(TwentyFiveLive::Client).to receive(:call).and_return(true)
    allow(UniversityCalendar::IcsImport).to receive(:call).and_return(import_result)
    allow(UniversityCalendarEvent).to receive(:detect_term_dates).and_return({ start_date: nil, end_date: nil })
  end

  it "refreshes the 25Live data, imports the feed, and returns the import result" do
    expect(described_class.perform_now).to eq(import_result)

    expect(TwentyFiveLive::Client).to have_received(:call)
    expect(UniversityCalendar::IcsImport).to have_received(:call)
  end

  it "belongs to the fixed concurrency group" do
    expect(described_class::CONCURRENCY_GROUP).to eq("UniversityCalendarSyncJob")
  end

  describe "25Live reference data" do
    it "reports a failure and still imports the feed" do
      error = StandardError.new("synthetic 25Live failure")
      allow(TwentyFiveLive::Client).to receive(:call).and_raise(error)
      allow(Rails.error).to receive(:report)

      expect(described_class.perform_now).to eq(import_result)

      expect(Rails.error).to have_received(:report).with(error, handled: true)
      expect(UniversityCalendar::IcsImport).to have_received(:call)
    end
  end

  describe "user calendar syncs" do
    let!(:opted_in) { user_with_calendar(sync_university_events: true) }
    let!(:opted_out) { user_with_calendar(sync_university_events: false) }

    it "queues nothing when the import changed nothing" do
      expect { described_class.perform_now }.not_to have_enqueued_job(CourseCalendars::SyncJob)
    end

    %i[created updated cancelled].each do |kind|
      context "when #{kind} events are the only change" do
        let(:import_result) { no_changes.merge(kind => 2, changed_categories: [ "academic" ]) }

        it "syncs only the users who opted in to university events" do
          expect(synced_user_ids { described_class.perform_now }).to eq([ opted_in.id ])
        end
      end
    end

    %w[holiday study_day].each do |category|
      context "when a #{category} changed" do
        let(:import_result) { no_changes.merge(created: 1, changed_categories: [ category, "academic" ]) }

        it "syncs every user with a course calendar" do
          expect(synced_user_ids { described_class.perform_now }).to contain_exactly(opted_in.id, opted_out.id)
        end
      end
    end

    context "when the import result has no categories" do
      let(:import_result) { { created: 1, updated: 0, cancelled: 0 } }

      it "treats the change as a non-holiday change" do
        expect(synced_user_ids { described_class.perform_now }).to eq([ opted_in.id ])
      end
    end

    context "with a user who has no course calendar" do
      let(:import_result) { no_changes.merge(created: 1, changed_categories: [ "holiday" ]) }
      let!(:without_calendar) { create(:user) }

      it "does not queue a sync for them" do
        expect(synced_user_ids { described_class.perform_now }).not_to include(without_calendar.id)
      end
    end
  end

  describe "term dates" do
    let(:year) { Time.zone.today.year }
    let!(:term) { create(:term, year: year, season: :fall) }

    it "fills in missing start and end dates" do
      allow(UniversityCalendarEvent).to receive(:detect_term_dates).with(year, "fall")
                                                                    .and_return({ start_date: Date.new(year, 9, 1), end_date: Date.new(year, 12, 20) })

      described_class.perform_now

      expect(term.reload).to have_attributes(start_date: Date.new(year, 9, 1), end_date: Date.new(year, 12, 20))
    end

    it "does not overwrite dates that are already set" do
      term.update!(start_date: Date.new(year, 8, 25), end_date: Date.new(year, 12, 18))
      allow(UniversityCalendarEvent).to receive(:detect_term_dates).and_return({ start_date: Date.new(year, 9, 1), end_date: Date.new(year, 12, 20) })

      described_class.perform_now

      expect(term.reload).to have_attributes(start_date: Date.new(year, 8, 25), end_date: Date.new(year, 12, 18))
    end

    it "leaves the term alone when no dates are detected" do
      expect { described_class.perform_now }.not_to(change { term.reload.updated_at })
    end

    it "skips terms from before last year" do
      old_term = create(:term, year: year - 2, season: :fall)

      described_class.perform_now

      expect(UniversityCalendarEvent).not_to have_received(:detect_term_dates).with(old_term.year, anything)
    end

    it "reports an error for one term and goes on to the next" do
      other = create(:term, year: year, season: :spring)
      allow(Rails.error).to receive(:report)
      allow(UniversityCalendarEvent).to receive(:detect_term_dates) do |_year, season|
        raise ArgumentError, "synthetic failure" if season.to_s == "fall"

        { start_date: Date.new(year, 1, 20), end_date: nil }
      end

      described_class.perform_now

      expect(Rails.error).to have_received(:report)
        .with(an_instance_of(ArgumentError), handled: true, context: { term_id: term.id })
      expect(other.reload.start_date).to eq(Date.new(year, 1, 20))
    end
  end
end
