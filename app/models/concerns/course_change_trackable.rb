# frozen_string_literal: true

# Marks the calendars of the users enrolled in a course as needing a sync
# when the course or one of its meeting times changes in a way a calendar
# shows (CourseCalendars::SyncMarker). Course and Course::MeetingTime include
# it and name the columns they watch with tracks_calendar_changes.
module CourseChangeTrackable
  extend ActiveSupport::Concern

  ENROLLMENT_CACHE_KEY = :course_change_enrollment_cache

  # Inside the block, "does this course have an enrollment" is asked once for
  # each course, not once for each save. flags: course_id => true/false that
  # the caller loaded for many courses in one query.
  def self.with_enrollment_cache(flags = {})
    Thread.current[ENROLLMENT_CACHE_KEY] = flags
    yield
  ensure
    Thread.current[ENROLLMENT_CACHE_KEY] = nil
  end

  def self.enrolled?(course_id)
    cache = Thread.current[ENROLLMENT_CACHE_KEY]
    return Enrollment.exists?(course_id: course_id) unless cache

    cache.key?(course_id) ? cache[course_id] : (cache[course_id] = Enrollment.exists?(course_id: course_id))
  end

  class_methods do
    # on: :update for a record that has no enrollment when it is new.
    def tracks_calendar_changes(*columns, course_id:, on: :save)
      define_method(:calendar_course_id) { public_send(course_id) }
      condition = -> { columns.any? { |column| saved_change_to_attribute?(column) } }

      on == :update ? after_update(:mark_enrolled_users_for_sync, if: condition) : after_save(:mark_enrolled_users_for_sync, if: condition)
      after_destroy :mark_enrolled_users_for_sync
    end
  end

  # Public for the changes that save no watched column: an instructor change
  # (Faculties::Ingest) and a room change (Course::MeetingTimeRoom).
  def mark_enrolled_users_for_sync
    CourseCalendars::SyncMarker.mark(calendar_course_id) if CourseChangeTrackable.enrolled?(calendar_course_id)
  end
end
