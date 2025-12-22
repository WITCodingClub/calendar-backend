# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::OauthCredentials", type: :request do
  let(:user) { create(:user) }
  let(:jwt_token) { JsonWebTokenService.encode(user_id: user.id) }
  let(:headers) { { "Authorization" => "Bearer #{jwt_token}" } }

  before do
    # Enable the v1 feature flag for API access
    Flipper.enable(FlipperFlags::V1, user)
  end

  describe "GET /api/user/oauth_credentials" do
    context "when user has no OAuth credentials" do
      it "returns an empty array" do
        get "/api/user/oauth_credentials", headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["oauth_credentials"]).to eq([])
      end
    end

    context "when user has one OAuth credential" do
      let!(:credential) do
        create(:oauth_credential,
               user: user,
               email: "user@example.com",
               provider: "google")
      end

      it "returns the credential without calendar" do
        get "/api/user/oauth_credentials", headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        credentials = json["oauth_credentials"]

        expect(credentials.length).to eq(1)
        expect(credentials[0]).to include(
          "id" => credential.public_id,
          "email" => "user@example.com",
          "provider" => "google",
          "has_calendar" => false,
          "calendar_id" => nil
        )
        expect(credentials[0]).to have_key("created_at")
      end
    end

    context "when user has multiple OAuth credentials with calendars" do
      let!(:credential1) do
        create(:oauth_credential,
               user: user,
               email: "personal@example.com",
               provider: "google")
      end
      let!(:calendar1) do
        create(:google_calendar,
               oauth_credential: credential1,
               google_calendar_id: "calendar1@google.com")
      end
      let!(:credential2) do
        create(:oauth_credential,
               user: user,
               email: "work@example.com",
               provider: "google")
      end
      let!(:calendar2) do
        create(:google_calendar,
               oauth_credential: credential2,
               google_calendar_id: "calendar2@google.com")
      end

      it "returns all credentials with calendar info" do
        get "/api/user/oauth_credentials", headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        credentials = json["oauth_credentials"]

        expect(credentials.length).to eq(2)

        cred1 = credentials.find { |c| c["id"] == credential1.public_id }
        expect(cred1).to include(
          "email" => "personal@example.com",
          "provider" => "google",
          "has_calendar" => true,
          "calendar_id" => "calendar1@google.com"
        )

        cred2 = credentials.find { |c| c["id"] == credential2.public_id }
        expect(cred2).to include(
          "email" => "work@example.com",
          "provider" => "google",
          "has_calendar" => true,
          "calendar_id" => "calendar2@google.com"
        )
      end
    end

    context "when user is not authenticated" do
      it "returns unauthorized" do
        get "/api/user/oauth_credentials"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "DELETE /api/user/oauth_credentials/:credential_id" do
    context "when deleting a valid credential" do
      let!(:credential1) do
        create(:oauth_credential,
               user: user,
               email: "first@example.com",
               provider: "google")
      end
      let!(:credential2) do
        create(:oauth_credential,
               user: user,
               email: "second@example.com",
               provider: "google")
      end

      it "successfully deletes the credential using internal ID" do
        expect {
          delete "/api/user/oauth_credentials/#{credential1.id}", headers: headers
        }.to change(OauthCredential, :count).by(-1)

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["message"]).to eq("OAuth credential disconnected successfully")

        expect(OauthCredential.exists?(credential1.id)).to be false
        expect(OauthCredential.exists?(credential2.id)).to be true
      end

      it "successfully deletes the credential using public_id" do
        expect {
          delete "/api/user/oauth_credentials/#{credential1.public_id}", headers: headers
        }.to change(OauthCredential, :count).by(-1)

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["message"]).to eq("OAuth credential disconnected successfully")

        expect(OauthCredential.exists?(credential1.id)).to be false
        expect(OauthCredential.exists?(credential2.id)).to be true
      end
    end

    context "when trying to delete the last credential" do
      let!(:credential) do
        create(:oauth_credential,
               user: user,
               email: "only@example.com",
               provider: "google")
      end

      it "prevents deletion and returns error" do
        expect {
          delete "/api/user/oauth_credentials/#{credential.id}", headers: headers
        }.not_to change(OauthCredential, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        json = response.parsed_body
        expect(json["error"]).to include("Cannot disconnect the last OAuth credential")
      end
    end

    context "when credential_id is missing" do
      it "returns bad request" do
        delete "/api/user/oauth_credentials/", headers: headers

        expect(response).to have_http_status(:not_found)
      end
    end

    context "when credential does not exist" do
      it "returns not found" do
        delete "/api/user/oauth_credentials/99999", headers: headers

        expect(response).to have_http_status(:not_found)
        json = response.parsed_body
        expect(json["error"]).to eq("OAuth credential not found")
      end
    end

    context "when trying to delete another user's credential" do
      let(:other_user) { create(:user) }
      let!(:other_credential) do
        create(:oauth_credential,
               user: other_user,
               email: "other@example.com",
               provider: "google")
      end

      it "returns not found" do
        delete "/api/user/oauth_credentials/#{other_credential.id}", headers: headers

        expect(response).to have_http_status(:not_found)
        json = response.parsed_body
        expect(json["error"]).to eq("OAuth credential not found")
      end
    end

    context "when user is not authenticated" do
      it "returns unauthorized" do
        credential = create(:oauth_credential, user: user, provider: "google")

        delete "/api/user/oauth_credentials/#{credential.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when credential has an associated calendar" do
      let!(:credential1) do
        create(:oauth_credential,
               user: user,
               email: "first@example.com",
               provider: "google")
      end
      let!(:credential2) do
        create(:oauth_credential,
               user: user,
               email: "second@example.com",
               provider: "google")
      end
      let!(:calendar) do
        create(:google_calendar,
               oauth_credential: credential1,
               google_calendar_id: "calendar@google.com")
      end

      it "successfully deletes the credential and calendar" do
        # Stub the calendar access revocation to avoid API calls
        allow_any_instance_of(GoogleCalendarService).to receive(:unshare_calendar_with_email)

        expect {
          delete "/api/user/oauth_credentials/#{credential1.id}", headers: headers
        }.to change(OauthCredential, :count).by(-1)
          .and change(GoogleCalendar, :count).by(-1)

        expect(response).to have_http_status(:ok)
        expect(OauthCredential.exists?(credential1.id)).to be false
        expect(GoogleCalendar.exists?(calendar.id)).to be false
      end
    end
  end
end
