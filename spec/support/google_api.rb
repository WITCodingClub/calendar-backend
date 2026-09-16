# frozen_string_literal: true

# Helpers for specs that reach the Google Calendar and OAuth APIs. The requests
# themselves are stubbed with WebMock, so the real client code runs.
module GoogleApiStubs
  GOOGLE_CALENDAR_API = "https://www.googleapis.com/calendar/v3"
  GOOGLE_REVOKE_URL   = "https://oauth2.googleapis.com/revoke"

  # The service account key lives in the encrypted credentials, which specs do
  # not have. A client that already holds a token skips the key exchange.
  def stub_google_service_account
    allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds)
      .and_return(Signet::OAuth2::Client.new(access_token: "synthetic-service-account-token"))
  end

  def google_calendar_list_url(calendar_id)
    "#{GOOGLE_CALENDAR_API}/users/me/calendarList/#{calendar_id}"
  end

  def google_acl_url(calendar_id, email)
    "#{GOOGLE_CALENDAR_API}/calendars/#{calendar_id}/acl/user:#{email}"
  end

  def google_revoke_url
    GOOGLE_REVOKE_URL
  end
end

RSpec.configure do |config|
  config.include GoogleApiStubs
end
