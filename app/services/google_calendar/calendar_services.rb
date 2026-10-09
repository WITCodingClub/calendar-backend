# frozen_string_literal: true

module GoogleCalendar
  # Builds an authorized Google::Apis::CalendarV3::CalendarService.
  #
  # The service account owns every calendar the app creates. A person's own
  # token writes the events and the person's calendar list. An expired token
  # is refreshed and saved before the service is returned.
  module CalendarServices
    SCOPE = "https://www.googleapis.com/auth/calendar"

    module_function

    def service_account
      build(service_account_credentials)
    end

    # Uses the person's primary Google credential.
    def for_user(user)
      build(user_authorization(user))
    end

    # Uses one linked Google account, for example a second email.
    def for_credential(credential)
      build(credential_authorization(credential))
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

    def user_authorization(user)
      raise "User has no Google credential" unless user.google_credential
      raise "User has no Google access token" if user.google_access_token.blank?

      credentials = refresh_credentials(
        access_token:  user.google_access_token,
        refresh_token: user.google_refresh_token,
        expires_at:    user.google_token_expires_at
      )

      if user.google_credential.token_expired?
        credentials.refresh!
        user.google_credential.update!(
          access_token:     credentials.access_token,
          token_expires_at: Time.zone.at(credentials.expires_at)
        )
        user.instance_variable_set(:@google_credential, nil)
      end

      credentials
    end

    def credential_authorization(credential)
      credentials = refresh_credentials(
        access_token:  credential.access_token,
        refresh_token: credential.refresh_token,
        expires_at:    credential.token_expires_at
      )

      if credential.token_expired?
        credentials.refresh!
        credential.update!(
          access_token:     credentials.access_token,
          token_expires_at: Time.zone.at(credentials.expires_at)
        )
      end

      credentials
    end

    def refresh_credentials(access_token:, refresh_token:, expires_at:)
      Google::Auth::UserRefreshCredentials.new(
        client_id:     Rails.application.credentials.dig(:google, :client_id),
        client_secret: Rails.application.credentials.dig(:google, :client_secret),
        scope:         [ SCOPE ],
        access_token:  access_token,
        refresh_token: refresh_token,
        expires_at:    expires_at
      )
    end
  end
end
