# frozen_string_literal: true

module CourseChangeTrackable
  extend ActiveSupport::Concern

  ENROLLMENT_CACHE_KEY = :course_change_enrollment_cache

  # Wrap bulk course-save operations in this block to batch-check enrollment existence
  # per course once rather than once per course save (avoids N+1).
  #
  # Pass a hash of course_id => true/false to start with flags that the caller
  # loaded for many courses in one query. The block then sends no EXISTS query
  # for those courses.
  def self.with_enrollment_cache(flags = {})
    Thread.current[ENROLLMENT_CACHE_KEY] = flags
    yield
  ensure
    Thread.current[ENROLLMENT_CACHE_KEY] = nil
  end

  included do
    # Mark all enrolled users' calendars as needing sync when course details change
    # A new course has no enrollments yet, so the check can only find none.
    after_update :mark_enrolled_users_for_sync, if: :saved_change_to_relevant_attributes?
    after_destroy :mark_enrolled_users_for_sync
  end

  # Public so the faculty importer can mark calendars itself. An instructor
  # change touches no column on courses, so the after_save callback never fires
  # for it.
  def mark_enrolled_users_for_sync
    # Skip expensive JOIN query when no one is enrolled in this course.
    # Within a bulk operation wrapped with with_enrollment_cache, the EXISTS check
    # is memoized per course_id to avoid N+1 queries.
    cache = Thread.current[ENROLLMENT_CACHE_KEY]
    has_enrollments = if cache
                        cache.key?(id) ? cache[id] : (cache[id] = Enrollment.exists?(course_id: id))
    else
                        Enrollment.exists?(course_id: id)
    end
    return unless has_enrollments

    CalendarSyncMarker.mark(id)
  end

  private

  def saved_change_to_relevant_attributes?
    # Track changes to any attributes that affect calendar display
    relevant_attrs = %w[title start_date end_date subject course_number section_number]
    relevant_attrs.any? { |attr| saved_change_to_attribute?(attr) }
  end
end
