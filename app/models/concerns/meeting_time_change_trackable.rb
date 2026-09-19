# frozen_string_literal: true

module MeetingTimeChangeTrackable
  extend ActiveSupport::Concern

  ENROLLMENT_CACHE_KEY = :meeting_time_enrollment_cache

  # Wrap bulk operations in this block to batch-check enrollment existence per
  # course once rather than once per meeting_time save (avoids N+1).
  def self.with_enrollment_cache
    Thread.current[ENROLLMENT_CACHE_KEY] = {}
    yield
  ensure
    Thread.current[ENROLLMENT_CACHE_KEY] = nil
  end

  included do
    # Mark all enrolled users' calendars as needing sync when meeting time changes
    after_save :mark_enrolled_users_for_sync, if: :saved_change_to_relevant_attributes?
    after_destroy :mark_enrolled_users_for_sync
  end

  # Rooms live in course_meeting_time_rooms, not in a column on this row, so a
  # room change saves nothing here and the callback above never fires.
  # Course::MeetingTimeRoom calls this directly when a room is linked or unlinked.
  def mark_enrolled_users_for_sync
    # Skip expensive JOIN query when no one is enrolled in this course.
    # Within a bulk operation wrapped with with_enrollment_cache, the EXISTS check
    # is memoized per course_id to avoid N+1 queries.
    cache = Thread.current[ENROLLMENT_CACHE_KEY]
    has_enrollments = if cache
                        cache.key?(course_id) ? cache[course_id] : (cache[course_id] = Enrollment.exists?(course_id: course_id))
    else
                        Enrollment.exists?(course_id: course_id)
    end
    return unless has_enrollments

    # Mark all users enrolled in this course as needing a calendar sync.
    # Select the same way NightlyCalendarSyncJob does, by the course_calendars
    # association. The old predicate looked for a course_calendar_id key in the
    # OAuth credential metadata. Nothing writes that key, so it matched no one
    # and no data change ever marked a calendar.
    # Using update_all for performance with bulk updates
    # First get distinct user IDs, then update them (Rails 8.2 compatibility)
    user_ids = User.joins(:enrollments)
                   .joins(:course_calendars)
                   .where(enrollments: { course_id: course_id })
                   .distinct
                   .pluck(:id)

    User.where(id: user_ids).update_all(calendar_needs_sync: true) if user_ids.any? # rubocop:disable Rails/SkipsModelValidations
  end

  private

  def saved_change_to_relevant_attributes?
    # Track changes to any attributes that affect calendar display
    relevant_attrs = %w[begin_time end_time day_of_week start_date end_date]
    relevant_attrs.any? { |attr| saved_change_to_attribute?(attr) }
  end
end
