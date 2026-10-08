# frozen_string_literal: true

# Marks the calendars of the users enrolled in a course as needing a sync.
#
# Select the same way NightlyCalendarSyncJob does, by the course_calendars
# association. The old predicate looked for a course_calendar_id key in the
# OAuth credential metadata. Nothing writes that key, so it matched no one and
# no data change ever marked a calendar.
module CalendarSyncMarker
  BATCH_KEY = :calendar_sync_marker_batch

  # Inside the block, mark collects the course IDs and marks the users of all
  # of them in one query when the block ends. Wrap code that changes many
  # courses in it, so it does not send one query for each course (#723).
  def self.batch
    return yield if Thread.current[BATCH_KEY]

    begin
      Thread.current[BATCH_KEY] = Set.new
      yield
    ensure
      # Mark also after an error: the writes before it are already saved.
      pending = Thread.current[BATCH_KEY]
      Thread.current[BATCH_KEY] = nil
      mark_now(pending) if pending.present?
    end
  end

  def self.mark(course_ids)
    pending = Thread.current[BATCH_KEY]
    if pending
      pending.merge(Array(course_ids))
    else
      mark_now(course_ids)
    end
  end

  def self.mark_now(course_ids)
    # First get distinct user IDs, then update them (Rails 8.2 compatibility).
    user_ids = User.joins(:enrollments)
                   .joins(:course_calendars)
                   .where(enrollments: { course_id: Array(course_ids) })
                   .distinct
                   .pluck(:id)

    User.where(id: user_ids).update_all(calendar_needs_sync: true) if user_ids.any? # rubocop:disable Rails/SkipsModelValidations
  end
end
