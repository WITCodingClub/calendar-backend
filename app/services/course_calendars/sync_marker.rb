# frozen_string_literal: true

module CourseCalendars
  # Marks the calendars of the users enrolled in a course as needing a sync,
  # for CourseCalendars::NightlySyncJob. Only users with a course calendar.
  module SyncMarker
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

    # A batch in which CourseChangeTrackable reads whether a course has an
    # enrollment from flags, a hash of course_id => true/false that the caller
    # loaded for many courses in one query. A course not in flags is checked and
    # added on its first save.
    def self.batch_with_enrollment_flags(flags, &)
      batch { CourseChangeTrackable.with_enrollment_cache(flags, &) }
    end

    # The flags for batch_with_enrollment_flags, in one query.
    def self.enrollment_flags(course_ids)
      flags = course_ids.index_with(false)
      Enrollment.where(course_id: course_ids).distinct.pluck(:course_id).each { |id| flags[id] = true }
      flags
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
      User.with_course_calendar
          .where(id: Enrollment.where(course_id: Array(course_ids)).select(:user_id))
          .update_all(calendar_needs_sync: true) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
