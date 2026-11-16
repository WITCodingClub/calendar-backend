# frozen_string_literal: true

module CourseCalendars
  # The per-user calendar lock. Every job that writes a person's calendar
  # takes it, so two of them never run at the same time for one person and
  # create the same remote events twice.
  #
  # Solid Queue puts the group in front of the key, so every such job names
  # the group of CourseCalendars::SyncJob. Solid Queue also frees a lock when
  # its duration ends, even while the job still runs, so every such job holds
  # it as long as the longest one, a full sync of a large schedule.
  module UserLock
    extend ActiveSupport::Concern

    DURATION = 1.hour

    def self.key(user_id)
      "google_calendar_sync_user_#{user_id}"
    end

    class_methods do
      # The block takes the job's first argument and returns the user id.
      def limits_concurrency_per_user(&user_id)
        limits_concurrency to: 1, group: CourseCalendars::SyncJob::CONCURRENCY_GROUP,
                           key: ->(first, *) { CourseCalendars::UserLock.key(user_id.call(first)) },
                           duration: DURATION
      end
    end
  end
end
