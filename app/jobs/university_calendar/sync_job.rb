# frozen_string_literal: true

module UniversityCalendar
  # Imports the university calendar from the 25Live ICS feed, syncs the
  # calendars of the users that a change reaches, and fills missing term dates.
  # TwentyFiveLive::SyncJob refreshes the 25Live reference data on its own
  # schedule (config/recurring.yml).
  class SyncJob < ApplicationJob
    queue_as :low

    # The concurrency group is part of every lock key, so it must not change when
    # the class is renamed. Jobs in the queue hold locks under this name.
    CONCURRENCY_GROUP = "UniversityCalendarSyncJob"

    limits_concurrency to: 1, group: CONCURRENCY_GROUP, key: -> { "university_calendar_sync" }

    def perform
      Rails.logger.info("Starting university calendar sync")

      result = UniversityCalendar::IcsImport.call

      Rails.logger.info("University calendar ICS sync complete: #{result}")

      any_changes = result[:created].positive? || result[:updated].positive? || result[:cancelled].positive?

      if any_changes
        no_class_changed = Array(result[:changed_categories]).any? { |category| UniversityCalendarEvent.no_class_category?(category) }
        trigger_user_calendar_syncs(no_class_changed:)
      end

      update_term_dates_from_events

      result
    end

    private

    def trigger_user_calendar_syncs(no_class_changed:)
      if no_class_changed
        CourseCalendars::SyncJob.perform_bulk_in_batch(CourseCalendars::ResyncAudience.all, reason: "holidays", force: true)
      else
        CourseCalendars::SyncJob.perform_bulk_in_batch(CourseCalendars::ResyncAudience.with_university_events,
                                                       reason: "university_events", force: true)
      end
    end

    def update_term_dates_from_events
      Term.where(year: (Time.zone.today.year - 1)..).find_each do |term|
        updates = TermDates.fill_missing(term)
        Rails.logger.info("Updated term #{term.name} with dates: #{updates}") if updates.any?
      rescue => e
        Rails.error.report(e, handled: true, context: { term_id: term.id })
      end
    end
  end
end
