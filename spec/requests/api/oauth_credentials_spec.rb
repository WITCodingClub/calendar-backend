# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Users OAuth credentials", type: :request do
  let(:user) { create(:user) }

  describe "GET /api/user/oauth_credentials" do
    it "lists a Microsoft credential with its provider and calendar" do
      create(:oauth_credential, user: user)
      calendar = create(:course_calendar, :microsoft, oauth_credential: create(:oauth_credential, :microsoft, user: user))

      get "/api/user/oauth_credentials", headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)
      microsoft = JSON.parse(response.body)["oauth_credentials"].find { |c| c["provider"] == "microsoft" }
      expect(microsoft).to include("has_calendar" => true, "calendar_id" => calendar.external_calendar_id, "needs_reauth" => false)
    end
  end

  describe "DELETE /api/user/oauth_credentials/:credential_id" do
    it "disconnects a Microsoft credential and keeps the session working" do
      create(:oauth_credential, user: user)
      microsoft = create(:oauth_credential, :microsoft, user: user)
      headers   = auth_headers_for(user)

      delete "/api/user/oauth_credentials/#{microsoft.public_id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(user.oauth_credentials.microsoft).to be_empty

      get "/api/user/oauth_credentials", headers: headers
      expect(response).to have_http_status(:ok)
    end

    # Only the Google account that signed the person in ends the sessions. The
    # factory gives a credential the person's own email, which is that account.
    it "ends the session when the Google sign-in account is disconnected" do
      google  = create(:oauth_credential, user: user)
      create(:oauth_credential, user: user, email: Faker::Internet.email)
      headers = auth_headers_for(user)

      delete "/api/user/oauth_credentials/#{google.public_id}", headers: headers

      expect(response).to have_http_status(:ok)

      get "/api/user/oauth_credentials", headers: headers
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
