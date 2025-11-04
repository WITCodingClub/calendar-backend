# frozen_string_literal: true

module MeetingTimeChangeTrackable
  extend ActiveSupport::Concern

  included do
    # Mark all enrolled users' calendars as needing sync when meeting time changes
    after_save :mark_enrolled_users_for_sync, if: :saved_change_to_relevant_attributes?
    after_destroy :mark_enrolled_users_for_sync
  end

  private

  def saved_change_to_relevant_attributes?
    # Track changes to any attributes that affect calendar display
    relevant_attrs = %w[begin_time end_time day_of_week start_date end_date room_id]
    relevant_attrs.any? { |attr| saved_change_to_attribute?(attr) }
  end

  def mark_enrolled_users_for_sync
    # Mark all users enrolled in this course as needing a calendar sync
    # Only mark users who have Google OAuth credentials with a course calendar ID set
    # Using update_all for performance with bulk updates
    User.joins(:enrollments)
        .joins(:oauth_credentials)
        .where(enrollments: { course_id: course_id })
        .where(oauth_credentials: { provider: "google" })
        .where("oauth_credentials.metadata->>'course_calendar_id' IS NOT NULL")
        .distinct
        .update_all(calendar_needs_sync: true) # rubocop:disable Rails/SkipsModelValidations
  end
end
