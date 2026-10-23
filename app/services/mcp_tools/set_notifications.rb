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
    # not_changed is there only when the student did not confirm.
    output_schema(
      Schemas.object(
        {
          notifications_disabled:       Schemas::BOOLEAN,
          notifications_disabled_until: Schemas.nullable(Schemas::DATE_TIME),
          not_changed:                  Schemas::NOT_CHANGED
        },
        optional: %i[not_changed]
      )
    )
    links do
      [
        page_link(
          name:        "wit-calendar-notifications",
          title:       "Notification settings on WIT Calendar",
          url:         page_url(:dashboard_notifications_url),
          description: "Pause or resume your reminders."
        )
      ]
    end

    def perform(disabled:, duration_hours: nil)
      authorize user, :update?

      duration = disabled && duration_hours && parse_duration(duration_hours)

      # user.updated_at changes on each pause and resume, so an answer
      # cannot make the change twice.
      with_confirmation(change_message(disabled, duration), unchanged: -> { current }, version: record_version(user)) do
        if disabled
          duration ? user.disable_notifications!(duration: duration) : user.disable_notifications!
        else
          # The same steps as Api::NotificationsController#enable: the next sync
          # puts the reminders back on every event.
          user.enable_notifications!
          user.update_column(:calendar_needs_sync, true) # rubocop:disable Rails/SkipsModelValidations
          CourseCalendars::SyncJob.perform_later(user, force: true)
        end

        current
      end
    end

    private

    def current
      { notifications_disabled: user.notifications_disabled?, notifications_disabled_until: user.notifications_disabled_until }
    end

    # Whole minutes, so the confirmation message says what is stored.
    def parse_duration(hours)
      hours = Float(hours, exception: false)
      raise ToolError, "duration_hours must be between 0 and #{MAX_HOURS}" unless hours&.positive? && hours <= MAX_HOURS

      minutes = (hours * 60).round
      raise ToolError, "duration_hours must be at least one minute (0.0167 hours)" if minutes < 1

      minutes.minutes
    end

    # Nil when reminders are on and the call turns them on, so nothing
    # changes. The message has no clock time, so it is the same on the retry.
    def change_message(disabled, duration)
      return if !disabled && !user.notifications_disabled?

      change = if !disabled
                 "Turn the reminders of all your calendar events on again."
      elsif duration
                 "Turn off the reminders of all your calendar events for #{describe_duration(duration)}."
      else
                 "Turn off the reminders of all your calendar events until you turn them on again."
      end

      "#{change}\nNow: #{describe_current}."
    end

    # "2 hours", "1 hour and 30 minutes", "1 minute".
    def describe_duration(duration)
      hours, minutes = (duration.to_i / 60).divmod(60)
      parts = []
      parts << "#{hours} #{hours == 1 ? 'hour' : 'hours'}" if hours.positive?
      parts << "#{minutes} #{minutes == 1 ? 'minute' : 'minutes'}" if minutes.positive?
      parts.join(" and ")
    end

    def describe_current
      return "the reminders are on" unless user.notifications_disabled?
      return "the reminders are off until you turn them on again" if user.notifications_disabled_until > 50.years.from_now

      until_time = user.notifications_disabled_until.in_time_zone("America/New_York")
      "the reminders are off until #{until_time.strftime('%B %-d, %Y at %-I:%M %p')} (Eastern time)"
    end
  end
end
