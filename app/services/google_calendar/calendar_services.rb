# frozen_string_literal: true

module GoogleCalendar
  # Builds an authorized Google::Apis::CalendarV3::CalendarService.
  #
  # The service account owns every calendar the app creates. A person's own
  # token writes the events and the person's calendar list. An expired token
  # is refreshed and saved before the service is returned
  # (OauthCredential#google_authorization).
  module CalendarServices
    module_function

    def service_account
      build(service_account_credentials)
    end

    # Uses the person's primary Google credential.
    def for_user(user)
      credential = user.google_credential
      raise "User has no Google credential" unless credential

      for_credential(credential)
    end

    # Uses one linked Google account, for example a second email.
    def for_credential(credential)
      build(credential.google_authorization)
    end

    def build(authorization)
      service = Google::Apis::CalendarV3::CalendarService.new
      service.authorization = authorization
      service
    end

    def service_account_credentials
      service_account_config = Rails.application.credentials.dig(:google, :service_account)
      credentials_json       = service_account_config.is_a?(String) ? service_account_config : service_account_config.to_json

      Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: StringIO.new(credentials_json),
        scope:       Google::Apis::CalendarV3::AUTH_CALENDAR
      )
    end
  end
end
