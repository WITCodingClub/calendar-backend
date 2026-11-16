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

    # Full sync of courses, finals, and university events. Past finals and
    # university events go to CourseCalendars::HistoricalSyncJob when
    # backfill_historical is true, so this run ends quickly.
    def sync_schedule(force: false, backfill_historical: force)
      services = Providers.services_for(user)

      desired = events.class_events + events.final_exam_events + events.university_events

      result = each_provider(services) { |service| service.update_calendar_events(desired, force: force) }

      # update_calendar_events keeps every past event, so the past university
      # events the user no longer wants are deleted only here.
      UniversityEventPruner.new(user).call

      # Put back any friend meeting whose calendar was made again, for example
      # after a Microsoft placement move. Then take off each friend who
      # declined the invitation in Google or Outlook.
      publisher = FriendMeetings::Publisher.new(user, services: services)
      publisher.publish_missing
      publisher.remove_declined

      mark_synced(result)
      CourseCalendars::HistoricalSyncJob.perform_later(user, force: force) if backfill_historical && result

      result
    end

    # Past finals and university events. They are stable, so this only makes
    # and updates events, and deletes none.
    def sync_historical(force: false)
      services = Providers.services_for(user)
      desired  = events.final_exam_events(time_scope: :past) + events.university_events(time_scope: :past)
      return if desired.empty?

      each_provider(services) { |service| service.update_specific_events(desired, force: force) }
    end

    private

    # Runs the block for each provider and adds up the stats. A provider that
    # fails, for example with a revoked Google token, is reported and the others
    # still run. When every provider fails, the first error is raised, so the
    # job fails and the executor reports it. No provider gives nil, like a sync
    # that did not run.
    def each_provider(services)
      errors  = []
      results = services.map do |service|
        yield service
      rescue StandardError => e
        errors << [ e, service ]
        nil
      end

      raised = errors.shift.first if errors.any? && errors.size == services.size
      # A rate limit also fails the run when another provider worked. The job
      # then retries later (docs/google-calendar-rate-limits.md), and the user
      # is not recorded as synced. Syncing the other provider again changes
      # nothing.
      raised ||= errors.delete(errors.find { |error, _| error.is_a?(RateLimitError) })&.first
      errors.each do |error, service|
        Rails.error.report(error, handled: true, context: { user_id: user.id, provider: service.class.name })
      end
      raise raised if raised

      results.compact.reduce { |total, stats| total.merge(stats) { |_key, a, b| a + b } }
    end

    def mark_synced(result)
      return unless result && (result[:created] > 0 || result[:updated] > 0 || result[:skipped] > 0)

      user.update_columns(last_calendar_sync_at: Time.current, calendar_needs_sync: false) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
