# frozen_string_literal: true

module CourseCalendars
  # A provider event as the person left it, read back for
  # CourseCalendars::EventEdits.
  #
  # start_time and end_time are in SchoolTimeZone. The end of an all-day event
  # is the midnight after its last day, as both providers send it.
  # recurrence_changed is true when the person changed the recurrence: each
  # provider compares a recurrence in its own form. raw is the provider's own
  # answer, for the provider's next call.
  RemoteEvent = Data.define(:id, :summary, :location, :start_time, :end_time, :all_day, :recurrence_changed, :raw)
end
