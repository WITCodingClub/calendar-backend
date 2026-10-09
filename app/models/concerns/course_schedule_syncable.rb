# frozen_string_literal: true

# Calendar sync entry points on User. The work happens in CourseCalendars:
#
# - CourseCalendars::ScheduleSyncer sends the events to each provider.
# - CourseCalendars::EventBuilder builds the course, final exam, and
#   university events.
# - CourseCalendars::RecurrenceBuilder builds the dates and recurrence lines.
# - CourseCalendars::UniversityEventPruner deletes unwanted university events.
#
# These methods only delegate, so that every caller keeps working.
module CourseScheduleSyncable
  extend ActiveSupport::Concern

  def sync_course_schedule(force: false, backfill_historical: force)
    course_schedule_syncer.sync_schedule(force: force, backfill_historical: backfill_historical)
  end

  # Intelligent partial sync - only sync specific enrollments
  def sync_enrollments(enrollment_ids, force: false)
    course_schedule_syncer.sync_enrollments(enrollment_ids, force: force)
  end

  # Sync a single meeting time immediately (for preference changes)
  def sync_meeting_time(meeting_time_id, force: true)
    course_schedule_syncer.sync_meeting_time(meeting_time_id, force: force)
  end

  # Quick sync - only update stale events (not synced in last hour)
  def quick_sync
    sync_course_schedule(force: false)
  end

  # Force sync - update all events regardless of staleness
  def force_sync
    sync_course_schedule(force: true)
  end

  # Backfill past finals and university events — called by CourseCalendars::HistoricalSyncJob.
  def sync_historical_events(force: false)
    course_schedule_syncer.sync_historical(force: force)
  end

  # Sync a single final exam immediately (for preference changes)
  def sync_final_exam(final_exam_id, force: true)
    course_schedule_syncer.sync_final_exam(final_exam_id, force: force)
  end

  delegate :find_first_meeting_date, :parse_time, :build_recurrence_rule,
           :final_exam_date_for_course, :earliest_final_exam_date_for_term,
           :earliest_finals_period_event_for_term, :build_recurrence_with_exclusions,
           :build_holiday_exdates, :holidays_for_meeting_time, :preload_holidays_for_user!,
           :format_exdate,
           to: :course_schedule_recurrence

  delegate :tbd_location?, :tbd_building?, :tbd_room?, :final_exam_scope, :university_event_scope,
           to: :course_schedule_events

  def build_university_events_for_sync(time_scope: :future)
    course_schedule_events.university_events(time_scope: time_scope)
  end

  def build_finals_events_for_sync(time_scope: :future)
    course_schedule_events.finals_events(time_scope: time_scope)
  end

  # @return [Integer] the number of events deleted
  def prune_unwanted_university_events
    CourseCalendars::UniversityEventPruner.new(self).call
  end

  # @param service [#course_calendar, #delete_events] one provider service
  def prune_unwanted_university_events_with(service)
    CourseCalendars::UniversityEventPruner.new(self).prune_with(service)
  end

  def wanted_university_event_ids(candidate_ids)
    CourseCalendars::UniversityEventPruner.new(self).wanted_ids(candidate_ids)
  end

  # Add a method to handle calendar deletion/cleanup
  def delete_course_calendar
    course_calendar = CourseCalendar.google.for_user(self).first
    return if course_calendar.blank?

    google_service = GoogleCalendar::Provider.new(self)
    service_account_service = google_service.send(:service_account_calendar_service)

    service_account_service.delete_calendar(course_calendar.external_calendar_id)

    # Destroy the CourseCalendar record (this will cascade delete all associated events)
    course_calendar.destroy
  rescue Google::Apis::Error => e
    Rails.logger.error "Failed to delete calendar: #{e.message}"
  end

  def create_or_get_course_calendar
    GoogleCalendar::Provider.new(self).create_or_get_course_calendar
  end

  private

  # One builder for each user object. The builders memoize the final exam,
  # finals period, and holiday lookups, so these caches live as long as the
  # user object, as they did before the move to CourseCalendars.
  def course_schedule_recurrence
    @course_schedule_recurrence ||= CourseCalendars::RecurrenceBuilder.new(self)
  end

  def course_schedule_events
    @course_schedule_events ||= CourseCalendars::EventBuilder.new(self, recurrence: course_schedule_recurrence)
  end

  def course_schedule_syncer
    CourseCalendars::ScheduleSyncer.new(self, events: course_schedule_events)
  end
end
