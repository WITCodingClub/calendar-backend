# frozen_string_literal: true

module CourseChangeTrackable
  extend ActiveSupport::Concern

  ENROLLMENT_CACHE_KEY = :course_change_enrollment_cache

  # Wrap bulk course-save operations in this block to batch-check enrollment existence
  # per course once rather than once per course save (avoids N+1).
  def self.with_enrollment_cache
    Thread.current[ENROLLMENT_CACHE_KEY] = {}
    yield
  ensure
    Thread.current[ENROLLMENT_CACHE_KEY] = nil
  end

  included do
    # Mark all enrolled users' calendars as needing sync when course details change
    after_save :mark_enrolled_users_for_sync, if: :saved_change_to_relevant_attributes?
    after_destroy :mark_enrolled_users_for_sync
  end

  private

  def saved_change_to_relevant_attributes?
    # Track changes to any attributes that affect calendar display
    relevant_attrs = %w[title start_date end_date subject course_number section_number]
    relevant_attrs.any? { |attr| saved_change_to_attribute?(attr) }
  end

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

    # Mark all users enrolled in this course as needing a calendar sync
    # Only mark users who have Google OAuth credentials with a course calendar ID set
    # Using update_all for performance with bulk updates
    # First get distinct user IDs, then update them (Rails 8.2 compatibility)
    user_ids = User.joins(:enrollments)
                   .joins(:oauth_credentials)
                   .where(enrollments: { course_id: id })
                   .where(oauth_credentials: { provider: "google" })
                   .where("oauth_credentials.metadata->>'course_calendar_id' IS NOT NULL")
                   .distinct
                   .pluck(:id)

    User.where(id: user_ids).update_all(calendar_needs_sync: true) if user_ids.any? # rubocop:disable Rails/SkipsModelValidations
  end
end
