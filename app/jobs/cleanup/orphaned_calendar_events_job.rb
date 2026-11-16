# frozen_string_literal: true

module Cleanup
  # Deletes CalendarEvent rows with no owner: no meeting time, final exam,
  # university event, or friend meeting. They are left when courses go in a
  # catalog refresh or meeting times are removed. Destroying a row enqueues
  # the delete of its remote event with its provider (CalendarEvent).
  class OrphanedCalendarEventsJob < ApplicationJob
    queue_as :low

    def perform(dry_run: false)
      Rails.logger.info "[Cleanup::OrphanedCalendarEventsJob] Starting (dry_run: #{dry_run})"

      orphaned_events = CalendarEvent.orphaned
      total_count = orphaned_events.count

      Rails.logger.info "[Cleanup::OrphanedCalendarEventsJob] Found #{total_count} orphaned events"

      return { total: total_count, deleted: 0, errors: 0 } if dry_run || total_count.zero?

      deleted_count = 0
      error_count = 0

      orphaned_events.includes(:course_calendar).find_each do |event|
        event.destroy!
        deleted_count += 1
      rescue => e
        Rails.error.report(e, handled: true, context: { calendar_event_id: event.id })
        error_count += 1
      end

      Rails.logger.info "[Cleanup::OrphanedCalendarEventsJob] Completed: deleted #{deleted_count}, errors #{error_count}"

      { total: total_count, deleted: deleted_count, errors: error_count }
    end
  end
end
