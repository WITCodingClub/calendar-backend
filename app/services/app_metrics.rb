# frozen_string_literal: true

# Reads the counts that Prometheus shows as gauges. Yabeda calls .collect on
# every scrape, from the exporter thread in the Puma process.
module AppMetrics
  JOB_COUNTS = {
    "ready"     => -> { SolidQueue::ReadyExecution.count },
    "scheduled" => -> { SolidQueue::ScheduledExecution.count },
    "claimed"   => -> { SolidQueue::ClaimedExecution.count },
    "blocked"   => -> { SolidQueue::BlockedExecution.count },
    "failed"    => -> { SolidQueue::FailedExecution.count }
  }.freeze

  class << self
    def collect
      # The exporter thread is not a request thread, so give its database
      # connections back to the pool when the counts are done.
      Rails.application.executor.wrap do
        measure("users")            { Yabeda.calendar.users.set({}, User.count) }
        measure("active_sessions")  { Yabeda.calendar.active_sessions.set({}, UserSession.active.count) }
        measure("google_calendars") { Yabeda.calendar.google_calendars.set({}, CourseCalendar.google.count) }

        JOB_COUNTS.each do |state, count|
          measure("jobs #{state}") { Yabeda.calendar.jobs.set({ state: state }, count.call) }
        end
      end
    end

    private

    # One failed count must not fail the whole scrape. Prometheus would then
    # mark the app as down and drop the request and job metrics with it.
    def measure(name)
      yield
    rescue StandardError => e
      Rails.logger.warn("Metrics: could not count #{name}: #{e.class}: #{e.message}")
    end
  end
end
