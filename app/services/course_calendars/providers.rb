# frozen_string_literal: true

module CourseCalendars
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
  #   #create_friend_meeting_event(meeting, invite:)          -> CalendarEvent or nil
  #   #update_friend_meeting_event(row, meeting, attendees:)  -> CalendarEvent or nil
  #   #delete_friend_meeting_event(row)                       -> deletes the event and the row
  #
  # GoogleCalendar::Provider and MicrosoftGraph::CalendarProvider implement it.
  module Providers
    module_function

    # Google joins only when the person has a Google credential: without one,
    # every Google call raises. Microsoft joins only when its flag is on for
    # the person and they have a Microsoft calendar. A person with neither
    # gets no services, and the sync does nothing.
    def services_for(user)
      microsoft = MicrosoftGraph.enabled_for?(user) && CourseCalendar.microsoft.for_user(user).exists?

      services = []
      services << GoogleCalendar::Provider.new(user) if user.google_credential.present?
      services << MicrosoftGraph::CalendarProvider.new(user) if microsoft
      services
    end

    # Adds the stats of each provider. One provider gives back its own hash, and
    # no provider gives nil, like a sync that did not run.
    def merge_stats(results)
      results.compact.reduce { |total, stats| total.merge(stats) { |_key, a, b| a + b } }
    end
  end
end
