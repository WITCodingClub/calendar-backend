# frozen_string_literal: true

module Notifications
  # Turns the reminders of every calendar event off or on again. The API, the
  # dashboard and the MCP tool all call this, so each one queues the same sync:
  # the sync takes the reminders off each event or puts them back.
  class Toggle
    def self.call(user, disabled:, duration: nil)
      if disabled
        user.disable_notifications!(duration: duration)
      else
        user.enable_notifications!
      end

      user.update_column(:calendar_needs_sync, true) # rubocop:disable Rails/SkipsModelValidations
      CourseCalendars::SyncJob.perform_later(user, force: true)
    end
  end
end
