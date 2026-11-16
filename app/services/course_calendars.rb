# frozen_string_literal: true

module CourseCalendars
  # Starts one sync of the person's calendars after something that shapes
  # their events changed: a preference, a setting, their courses, or a new
  # calendar. Every caller goes through here, so a person whose sync reaches
  # no provider gets no job. With force, every event gets a provider call,
  # and the edits the person made in Google or Outlook are lost
  # (CourseCalendars::Provider). Returns whether a sync was queued.
  def self.resync(user, force:)
    return false unless Providers.syncs?(user)

    SyncJob.perform_later(user, force: force)
    true
  end
end
