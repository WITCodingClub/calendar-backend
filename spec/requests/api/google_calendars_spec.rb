# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::GoogleCalendars", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }
  let(:service) { instance_double(GoogleCalendar::Provider, create_or_get_course_calendar: "cal-1", remove_calendar_from_user_list_for_email: nil, unshare_calendar_with_email: nil) }

  def json = response.parsed_body

  def state_from(oauth_url)
    GoogleSignIn::OauthState.verify_state(Rack::Utils.parse_query(URI(oauth_url).query)["state"])
  end

  before { allow(GoogleCalendar::Provider).to receive(:new).and_return(service) }

  describe "POST /api/user/google_calendar" do
    it "answers INTERNAL_ERROR and reports the error when the calendar service fails" do
      create(:oauth_credential, user: user, email: "linked@example.com")
      allow(service).to receive(:create_or_get_course_calendar).and_raise(StandardError, "boom")
      allow(Rails.error).to receive(:report)

      post "/api/user/google_calendar", params: { email: "linked@example.com" }, headers: headers

      expect(response).to have_http_status(:internal_server_error)
      expect(json).to eq("error" => "Failed to request Google Calendar", "code" => "INTERNAL_ERROR")
      expect(Rails.error).to have_received(:report).with(an_instance_of(StandardError), handled: true, context: { user_id: user.id })
    end

    it "does not treat the Google account of another user as connected" do
      create(:oauth_credential, user: create(:user), email: "other@example.com")

      post "/api/user/google_calendar", params: { email: "other@example.com" }, headers: headers

      expect(json["message"]).to eq("OAuth required")
      expect(GoogleCalendar::Provider).not_to have_received(:new)
    end
  end

  describe "POST /api/user/google_calendar/emails" do
    it "answers UNPROCESSABLE_CONTENT when no Google account is connected yet" do
      post "/api/user/google_calendar/emails", params: { email: "new@example.com" }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("VALIDATION_FAILED")
      expect(json["error"]).to eq("Complete Google OAuth for at least one email first.")
    end

    it "returns an OAuth url for an email that is not connected" do
      create(:oauth_credential, user: user, email: "first@example.com")

      post "/api/user/google_calendar/emails", params: { email: " second@example.com " }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json).to include("message" => "OAuth required for this email", "email" => "second@example.com")
      expect(state_from(json["oauth_url"])).to include("user_id" => user.id, "email" => "second@example.com")
    end

    it "shares the calendar with an email that is connected" do
      create(:oauth_credential, user: user, email: "first@example.com")
      create(:oauth_credential, user: user, email: "second@example.com")

      post "/api/user/google_calendar/emails", params: { email: "second@example.com" }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json).to eq("message" => "Calendar shared with email", "calendar_id" => "cal-1")
    end

    it "answers INTERNAL_ERROR and reports the error when the calendar service fails" do
      create(:oauth_credential, user: user, email: "first@example.com")
      allow(service).to receive(:create_or_get_course_calendar).and_raise(StandardError, "boom")
      allow(Rails.error).to receive(:report)

      post "/api/user/google_calendar/emails", params: { email: "first@example.com" }, headers: headers, as: :json

      expect(response).to have_http_status(:internal_server_error)
      expect(json).to eq("error" => "Failed to add email to Google Calendar", "code" => "INTERNAL_ERROR")
      expect(Rails.error).to have_received(:report).with(an_instance_of(StandardError), handled: true, context: { user_id: user.id })
    end
  end

  describe "DELETE /api/user/google_calendar/emails" do
    it "asks for an email" do
      delete "/api/user/google_calendar/emails", params: { email: " " }, headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(json).to eq("error" => "email is required", "code" => "BAD_REQUEST")
    end

    it "answers NOT_FOUND for an email of another user" do
      other = create(:oauth_credential, user: create(:user), email: "other@example.com")

      delete "/api/user/google_calendar/emails", params: { email: other.email }, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(OauthCredential.exists?(other.id)).to be(true)
    end

    it "answers NOT_FOUND when the account has no course calendar" do
      credential = create(:oauth_credential, user: user, email: "first@example.com")

      delete "/api/user/google_calendar/emails", params: { email: credential.email }, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(json).to eq("error" => "No Google Calendar found", "code" => "NOT_FOUND")
      expect(OauthCredential.exists?(credential.id)).to be(true)
    end

    it "removes the email when the user has a course calendar" do
      primary = create(:oauth_credential, user: user, email: "first@example.com")
      create(:course_calendar, oauth_credential: primary)
      extra = create(:oauth_credential, user: user, email: "second@example.com")

      delete "/api/user/google_calendar/emails", params: { email: extra.email }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["message"]).to eq("email removed from Google Calendar association")
      expect(OauthCredential.exists?(extra.id)).to be(false)
      expect(service).to have_received(:unshare_calendar_with_email).with(CourseCalendar.last.external_calendar_id, "second@example.com")
    end

    it "answers INTERNAL_ERROR and reports the error when removal fails" do
      primary = create(:oauth_credential, user: user, email: "first@example.com")
      create(:course_calendar, oauth_credential: primary)
      allow_any_instance_of(OauthCredential).to receive(:destroy!).and_raise(StandardError, "boom") # rubocop:disable RSpec/AnyInstance
      allow(Rails.error).to receive(:report)

      delete "/api/user/google_calendar/emails", params: { email: primary.email }, headers: headers, as: :json

      expect(response).to have_http_status(:internal_server_error)
      expect(json).to eq("error" => "Failed to remove email from Google Calendar", "code" => "INTERNAL_ERROR")
    end
  end
end
