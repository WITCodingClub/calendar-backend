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

    # The feed runs once a week, so a feed that is down gets two more tries.
    retry_on IcsImport::FetchError, wait: 1.hour, attempts: 3

    def perform
      Rails.logger.info("Starting university calendar sync")

      result = UniversityCalendar::IcsImport.call

      Rails.logger.info("University calendar ICS sync complete: #{result}")

      any_changes = result[:created].positive? || result[:updated].positive? || result[:cancelled].positive?

      self.class.resync_users(result[:changed_categories]) if any_changes

      update_term_dates_from_events

      result
    end

    # Queues the calendar syncs that a change to events in these categories
    # needs. A no-class category changes the class days of every user; any
    # other category reaches only the users who sync university events.
    def self.resync_users(changed_categories)
      if Array(changed_categories).any? { |category| UniversityCalendarEvent.no_class_category?(category) }
        CourseCalendars::SyncJob.perform_bulk_in_batch(CourseCalendars::ResyncAudience.all, reason: "holidays", force: true)
      else
        CourseCalendars::SyncJob.perform_bulk_in_batch(CourseCalendars::ResyncAudience.with_university_events,
                                                       reason: "university_events", force: true)
      end
    end

    private

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
