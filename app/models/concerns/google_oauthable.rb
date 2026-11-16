# frozen_string_literal: true

# The Google credentials of a user. A user can link several Google accounts;
# the course calendar is shared with each of them.
module GoogleOauthable
  extend ActiveSupport::Concern

  def google_credentials
    oauth_credentials.google
  end

  def google_credential_for_email(email)
    google_credentials.find_by(email: email)
  end

  # The account that syncs the course calendar: the first one linked.
  def google_credential
    google_credentials.order(:created_at).first
  end
end
