# frozen_string_literal: true

# Picks the calendar provider services that one person's sync runs through.
#
# Every provider service answers the same small interface:
#
#   new(user)
#   #course_calendar                         -> CourseCalendar or nil
#   #create_or_get_course_calendar           -> the external calendar id
#   #update_calendar_events(events, force:)  -> { created:, updated:, skipped: }
#   #update_specific_events(events, force:)  -> { created:, updated:, skipped: }
#   #delete_events(calendar_event_rows)      -> Integer
#
# GoogleCalendarService and MicrosoftGraphCalendarService implement it.
module CalendarProviders
  module_function

  # Google stays the default, so a person with no calendar yet takes the same
  # path as before. Microsoft joins only when its flag is on for the person
  # and they have a Microsoft calendar.
  def services_for(user)
    microsoft_enabled = MicrosoftGraph.enabled_for?(user)
    google            = user.google_credential.present?
    microsoft_calendar = (microsoft_enabled || !google) && CourseCalendar.microsoft.for_user(user).exists?

    services = []
    services << GoogleCalendarService.new(user) if google || !microsoft_calendar
    services << MicrosoftGraphCalendarService.new(user) if microsoft_enabled && microsoft_calendar
    services
  end

  # Adds the stats of each provider. One provider gives back its own hash, and
  # no provider gives nil, like a sync that did not run.
  def merge_stats(results)
    results.compact.reduce { |total, stats| total.merge(stats) { |_key, a, b| a + b } }
  end
end
