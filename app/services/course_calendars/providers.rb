# frozen_string_literal: true

module CourseCalendars
  # The calendar providers, by the name that CourseCalendar#provider and
  # OauthCredential#provider store. Models and jobs ask this registry, so only
  # the provider classes know their own jobs and token calls.
  #
  # Each class subclasses CourseCalendars::Provider and answers:
  #
  #   .delete_event_later(ref)          ref: { calendar_id:, oauth_credential_id:, event_id:, ical_uid: }
  #   .delete_calendar_later(calendar)  for a CourseCalendar row that is gone
  #   .refreshable?                     whether the app can refresh its tokens now
  #   .refresh_token!(credential)       refreshes and saves the access token
  #   .release_calendar(credential)     before the credential is destroyed
  #   .revoke_later(credential)         after the credential is destroyed
  module Providers
    CLASSES = {
      "google"    => "GoogleCalendar::Provider",
      "microsoft" => "MicrosoftGraph::CalendarProvider"
    }.freeze

    module_function

    def for(name)
      CLASSES.fetch(name.to_s).constantize
    end

    def refreshable_names
      CLASSES.keys.select { |name| self.for(name).refreshable? }
    end

    # Google joins only when the person has a Google credential: without one,
    # every Google call raises. Microsoft joins only when its flag is on for
    # the person and they have a Microsoft calendar. A person with neither
    # gets no services, and the sync does nothing.
    def services_for(user)
      services = []
      services << GoogleCalendar::Provider.new(user) if user.google_credential.present?
      if MicrosoftGraph.enabled_for?(user) && CourseCalendar.microsoft.for_user(user).exists?
        services << MicrosoftGraph::CalendarProvider.new(user)
      end
      services
    end
  end
end
