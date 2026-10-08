# frozen_string_literal: true

# Data that the extension collects from a student's Brightspace (D2L) account.
# See docs/brightspace.md for the API contract.
module Brightspace
  def self.table_name_prefix
    "brightspace_"
  end

  # The extension sends these sections for each class. A section that the
  # payload leaves out stays as it is.
  SECTIONS = %w[assignments announcements grades syllabus].freeze

  def self.enabled_for?(user)
    Flipper.enabled?(FlipperFlags::BRIGHTSPACE, user)
  end

  # Queues a calendar sync when the user has a calendar to sync to. The sync
  # adds, moves, and deletes deadline events.
  def self.queue_calendar_sync(user, force: false)
    return unless user.google_credential || user.course_calendars.microsoft.exists?

    GoogleCalendarSyncJob.perform_later(user, force: force)
  end
end
