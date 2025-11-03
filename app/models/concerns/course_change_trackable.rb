module CourseChangeTrackable
  extend ActiveSupport::Concern

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
    # Mark all users enrolled in this course as needing a calendar sync
    User.joins(:enrollments)
        .where(enrollments: { course_id: id })
        .where.not(google_course_calendar_id: nil)
        .update_all(calendar_needs_sync: true)
  end
end
