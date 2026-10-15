# frozen_string_literal: true

module McpTools
  # PATCH /api/user/notifications: pauses or resumes the reminders of every
  # calendar event.
  class SetNotifications < BaseWriteTool
    MAX_HOURS = 24 * 365

    tool_name "set_notifications"
    title "Pause or resume reminders"
    description "Turns off the reminders of all my calendar events, for a number of hours or until I turn " \
                "them on again, or turns them on again."
    requires_scope "notifications:write"
    input_schema(
      properties: {
        disabled:       { type: "boolean", description: "true turns reminders off, false turns them on." },
        duration_hours: {
          type:        "number",
          exclusiveMinimum: 0,
          maximum:     MAX_HOURS,
          description: "With disabled true: how long to keep reminders off. Leave it out to keep them off " \
                       "until they are turned on again."
        }
      },
      required: [ "disabled" ]
    )

    def perform(disabled:, duration_hours: nil)
      authorize user, :update?

      if disabled
        duration = duration_hours && parse_duration(duration_hours)
        duration ? user.disable_notifications!(duration: duration) : user.disable_notifications!
      else
        # The same steps as Api::NotificationsController#enable: the next sync
        # puts the reminders back on every event.
        user.enable_notifications!
        user.update_column(:calendar_needs_sync, true) # rubocop:disable Rails/SkipsModelValidations
        CourseCalendars::SyncJob.perform_later(user, force: true)
      end

      { notifications_disabled: user.notifications_disabled?, notifications_disabled_until: user.notifications_disabled_until }
    end

    private

    def parse_duration(hours)
      hours = Float(hours, exception: false)
      raise ToolError, "duration_hours must be between 0 and #{MAX_HOURS}" unless hours&.positive? && hours <= MAX_HOURS

      (hours * 3600).round.seconds
    end
  end
end
