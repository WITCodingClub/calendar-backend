# frozen_string_literal: true

module CourseCalendars
  # The calendar providers, by the name that CourseCalendar#provider and
  # OauthCredential#provider store. Models, jobs and controllers ask this
  # registry, so only the provider classes know their own jobs, token calls,
  # errors, and OAuth start URL.
  #
  # Each class subclasses CourseCalendars::Provider and answers:
  #
  #   .syncs_for?(user)                 whether a sync of the person reaches this provider
  #   .connect_path(user, **options)    the path that starts the OAuth connection
  #   .delete_event_later(ref)          ref: { calendar_id:, oauth_credential_id:, event_id:, ical_uid: }
  #   .delete_calendar_later(calendar)  for a CourseCalendar row that is gone
  #   .refreshable?                     whether the app can refresh its tokens now
  #   .refresh_token!(credential)       refreshes and saves the access token
  #   .invalid_grant?(error)            whether the error says the grant is refused for good
  #   .release_calendar(credential)     before the credential is destroyed
  #   .revoke_later(credential)         after the credential is destroyed
  #   AUTH_ERRORS, RATE_LIMIT_ERRORS, TRANSIENT_ERRORS, REMOVAL_RETRY_ERRORS
  #
  # A new provider is a new subclass and one new entry in CLASSES.
  module Providers
    CLASSES = {
      "google"    => "GoogleCalendar::Provider",
      "microsoft" => "MicrosoftGraph::CalendarProvider"
    }.freeze

    NAMES = CLASSES.keys.freeze

    module_function

    def for(name)
      CLASSES.fetch(name.to_s).constantize
    end

    def all
      CLASSES.values.map(&:constantize)
    end

    def refreshable_names
      NAMES.select { |name| self.for(name).refreshable? }
    end

    # The provider services that a sync of the person reaches. A person with
    # none gets no services, and the sync does nothing.
    def services_for(user)
      all.select { |provider| provider.syncs_for?(user) }.map { |provider| provider.new(user) }
    end

    # Whether a sync of the person would reach any provider, without building
    # the services.
    def syncs?(user)
      all.any? { |provider| provider.syncs_for?(user) }
    end

    # The provider refused the person's token. A retry cannot help until the
    # person connects the account again.
    def auth_errors
      all.flat_map { |provider| provider::AUTH_ERRORS }
    end

    def rate_limit_errors
      all.flat_map { |provider| provider::RATE_LIMIT_ERRORS }
    end

    def transient_errors
      all.flat_map { |provider| provider::TRANSIENT_ERRORS }
    end

    # The errors that a friend meeting removal retries besides
    # transient_errors (FriendMeetings::RemoveJob).
    def removal_retry_errors
      all.flat_map { |provider| provider::REMOVAL_RETRY_ERRORS }
    end

    def invalid_grant?(error)
      all.any? { |provider| provider.invalid_grant?(error) }
    end
  end
end
