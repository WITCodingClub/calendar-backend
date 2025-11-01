module GoogleOauthable
  extend ActiveSupport::Concern

  # Convenience methods for accessing Google OAuth credentials
  def google_credential
    @google_credential ||= oauth_credentials.find_by(provider: "google")
  end

  def google_uid
    google_credential&.uid
  end

  def google_access_token
    google_credential&.access_token
  end

  def google_refresh_token
    google_credential&.refresh_token
  end

  def google_token_expires_at
    google_credential&.token_expires_at
  end

  def google_course_calendar_id
    google_credential&.course_calendar_id
  end

  def google_course_calendar_id=(value)
    return unless google_credential
    google_credential.course_calendar_id = value
    google_credential.save!
  end

  def google_token_expired?
    google_credential&.token_expired? || false
  end

  def refresh_google_token!
    require "googleauth"
    return unless google_credential

    credentials = Google::Auth::UserRefreshCredentials.new(
      client_id: Rails.application.credentials.dig(:google, :client_id),
      client_secret: Rails.application.credentials.dig(:google, :client_secret),
      scope: ["https://www.googleapis.com/auth/calendar"],
      access_token: google_access_token,
      refresh_token: google_refresh_token,
      expires_at: google_token_expires_at
    )

    credentials.refresh!
    google_credential.update!(
      access_token: credentials.access_token,
      token_expires_at: Time.at(credentials.expires_at)
    )

    # Clear the cached credential
    @google_credential = nil
  end

  private

  def build_google_authorization
    require "googleauth"
    return unless google_credential

    credentials = Google::Auth::UserRefreshCredentials.new(
      client_id: Rails.application.credentials.dig(:google, :client_id),
      client_secret: Rails.application.credentials.dig(:google, :client_secret),
      scope: ["https://www.googleapis.com/auth/calendar"],
      access_token: google_access_token,
      refresh_token: google_refresh_token,
      expires_at: google_token_expires_at
    )

    # Refresh the token if needed
    if google_token_expired?
      credentials.refresh!
      google_credential.update!(
        access_token: credentials.access_token,
        token_expires_at: Time.at(credentials.expires_at)
      )
      # Clear the cached credential
      @google_credential = nil
    end

    credentials
  end
end
