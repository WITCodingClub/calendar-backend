# frozen_string_literal: true

module CourseCalendars
  # Sends one person's course schedule to each of their calendar providers.
  #
  # CourseCalendars::EventBuilder builds the events. This class gives them to
  # the provider services from CourseCalendars::Providers, adds up the stats,
  # records the sync time on the user, and starts the follow-up work.
  class ScheduleSyncer
    attr_reader :user, :events

    def initialize(user, events: EventBuilder.new(user))
      @user   = user
      @events = events
    end

    # Full sync of courses, finals, and university events.
    # Past finals and university events go to CourseCalendars::HistoricalSyncJob
    # when backfill_historical is true.
    def sync_schedule(force: false, backfill_historical: force)
      services = Providers.services_for(user)

      # Preload all holidays once over the full date range of all enrolled meeting times
      # to avoid N+1 queries in holidays_for_meeting_time (one query per unique date range)
      events.preload_holidays!

      # Build events from enrollments - each course can have multiple meeting times
      # Each meeting_time now represents a single day of the week
      desired = events.course_events(user.enrollments, prefer_valid_locations: true)

      # Add final exams and university events — future/current only so the fast
      # path completes quickly. Past events are deferred to CourseCalendars::HistoricalSyncJob.
      desired.concat(events.finals_events(time_scope: :future))
      desired.concat(events.university_events(time_scope: :future))

      result = Providers.merge_stats(services.map { |service| service.update_calendar_events(desired, force: force) })

      # Remove past university events the user no longer wants. update_calendar_events
      # keeps every past event, so this is the only place they get deleted.
      UniversityEventPruner.new(user).call

      # Put back any friend meeting whose calendar was made again, for example
      # after a Microsoft placement move.
      FriendMeetings::Publisher.new(user, services: services).publish_missing

      mark_synced(result, clear_needs_sync: true)

      # Backfill past events on force/nightly syncs (not routine quick_syncs).
      CourseCalendars::HistoricalSyncJob.perform_later(user, force: force) if backfill_historical && result

      result
    end

    # Intelligent partial sync - only sync specific enrollments
    def sync_enrollments(enrollment_ids, force: false)
      services = Providers.services_for(user)
      desired = events.course_events(user.enrollments.where(id: enrollment_ids), prefer_valid_locations: false)

      # Only sync these specific events
      result = Providers.merge_stats(services.map { |service| service.update_specific_events(desired, force: force) })
      mark_synced(result, clear_needs_sync: true)
      result
    end

    # Sync a single meeting time immediately (for preference changes)
    def sync_meeting_time(meeting_time_id, force: true)
      services = Providers.services_for(user)
      meeting_time = Course::MeetingTime.includes(course: [ :faculties ], rooms: :building).find_by(id: meeting_time_id)
      return unless meeting_time

      event = events.meeting_time_event(meeting_time)
      return unless event

      sync_one(services, event, force: force)
    end

    # Sync a single final exam immediately (for preference changes)
    def sync_final_exam(final_exam_id, force: true)
      services = Providers.services_for(user)
      final_exam = ::FinalExam.includes(course: :faculties).find_by(id: final_exam_id)
      return unless final_exam

      event = events.final_exam_event(final_exam)
      return unless event

      sync_one(services, event, force: force)
    end

    # Backfill past finals and university events — called by CourseCalendars::HistoricalSyncJob.
    # Uses update_specific_events (upsert only, no deletions) since past events are stable.
    def sync_historical(force: false)
      services = Providers.services_for(user)
      desired  = events.finals_events(time_scope: :past)
      desired.concat(events.university_events(time_scope: :past))
      return if desired.empty?

      Providers.merge_stats(services.map { |service| service.update_specific_events(desired, force: force) })
    end

    private

    def sync_one(services, event, force:)
      # Sync just this one event
      result = Providers.merge_stats(services.map { |service| service.update_specific_events([ event ], force: force) })
      mark_synced(result, clear_needs_sync: false)
      result
    end

    # Update last sync timestamp if sync was successful
    def mark_synced(result, clear_needs_sync:)
      return unless result && (result[:created] > 0 || result[:updated] > 0 || result[:skipped] > 0)

      # rubocop:disable Rails/SkipsModelValidations
      if clear_needs_sync
        user.update_columns(last_calendar_sync_at: Time.current, calendar_needs_sync: false)
      else
        user.update_column(:last_calendar_sync_at, Time.current)
      end
      # rubocop:enable Rails/SkipsModelValidations
    end
  end
end
