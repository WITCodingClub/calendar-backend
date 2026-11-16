# frozen_string_literal: true

module GoogleCalendar
  # Builds an authorized Google::Apis::CalendarV3::CalendarService.
  #
  # The service account owns every calendar the app creates. A person's own
  # token writes the events and the person's calendar list. An expired token
  # is refreshed and saved before the service is returned.
  module CalendarServices
    module_function

    def service_account
      build(service_account_credentials)
    end

    def for_user(user)
      credential = user.google_credential
      raise "User has no Google credential" unless credential

      for_credential(credential)
    end

    # Uses one linked Google account, for example a second email.
    def for_credential(credential)
      build(authorization(credential))
    end

    # The Google authorization for one credential. An expired token (or any
    # token, with refresh: true) is refreshed and saved first. A refused grant
    # marks the credential revoked.
    def authorization(credential, refresh: false)
      authorization = Google::Auth::UserRefreshCredentials.new(
        **GoogleCalendar.config.slice(:client_id, :client_secret),
        scope:         [ GoogleCalendar::CALENDAR_SCOPE ],
        access_token:  credential.access_token,
        refresh_token: credential.refresh_token,
        expires_at:    credential.token_expires_at
      )
      return authorization unless refresh || credential.token_expired?

      begin
        authorization.refresh!
      rescue Signet::AuthorizationError => e
        credential.mark_revoked!(e.message) if GoogleCalendar::Provider.invalid_grant?(e)
        raise
      end
      credential.update!(access_token: authorization.access_token, token_expires_at: Time.zone.at(authorization.expires_at))
      authorization
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
        scope:       GoogleCalendar::CALENDAR_SCOPE
      )
    end
  end
end
