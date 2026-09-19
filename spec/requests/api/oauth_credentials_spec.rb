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

    # The extension shows where the classes go, so the list carries the
    # placement of the calendar and whether the person can disconnect the row.
    it "gives the placement of each calendar and whether the credential can go" do
      google = create(:oauth_credential, user: user)
      create(:course_calendar, oauth_credential: google)
      create(:course_calendar, :primary, oauth_credential: create(:oauth_credential, :microsoft, user: user))

      get "/api/user/oauth_credentials", headers: auth_headers_for(user)

      credentials = JSON.parse(response.body)["oauth_credentials"]
      expect(credentials.find { |c| c["provider"] == "microsoft" }).to include("placement" => "primary", "removable" => true)
      # A Google calendar has no placement of its own, and this is the last one.
      expect(credentials.find { |c| c["provider"] == "google" }).to include("placement" => "separate", "removable" => false)
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

    it "disconnects the only Microsoft credential" do
      microsoft = create(:oauth_credential, :microsoft, user: user)

      delete "/api/user/oauth_credentials/#{microsoft.public_id}", headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)
      expect(user.oauth_credentials.reload).to be_empty
    end

    it "refuses the last Google credential" do
      google = create(:oauth_credential, user: user)
      create(:oauth_credential, :microsoft, user: user)

      delete "/api/user/oauth_credentials/#{google.public_id}", headers: auth_headers_for(user)

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to eq("Cannot disconnect your last Google account.")
      expect(OauthCredential.exists?(google.id)).to be(true)
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
