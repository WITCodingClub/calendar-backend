# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Users" do
  let(:user) { create(:user) }
  let(:jwt_token) { JsonWebTokenService.encode(user_id: user.id) }
  let(:headers) { { "Authorization" => "Bearer #{jwt_token}", "Content-Type" => "application/json" } }

  before do
    Flipper.enable(FlipperFlags::V1, user)
  end

  describe "POST /api/user/onboard" do
    context "with valid parameters" do
      it "creates a new user and returns JWT token" do
        post "/api/user/onboard",
             params: { email: "newuser@example.com", preferred_name: "John Doe" }.to_json,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["pub_id"]).to be_present
        expect(json["jwt"]).to be_present
        expect(json).to have_key("beta_access")
      end

      it "returns existing user for existing email" do
        existing_user = create(:user)
        create(:email, user: existing_user, email: "existing@example.com", primary: true)

        post "/api/user/onboard",
             params: { email: "existing@example.com", preferred_name: "Existing User" }.to_json,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["pub_id"]).to eq(existing_user.public_id)
      end

      it "handles names with only first name" do
        post "/api/user/onboard",
             params: { email: "single@example.com", preferred_name: "SingleName" }.to_json,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:ok)
      end
    end

    context "with invalid parameters" do
      it "returns bad request when email is missing" do
        post "/api/user/onboard",
             params: { preferred_name: "John Doe" }.to_json,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["error"]).to eq("Email is required")
      end

      it "returns bad request when preferred_name is missing" do
        post "/api/user/onboard",
             params: { email: "test@example.com" }.to_json,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["error"]).to eq("Preferred name is required")
      end
    end
  end

  describe "GET /api/user/email" do
    context "when user has a primary email" do
      before do
        create(:email, user: user, email: "primary@example.com", primary: true)
      end

      it "returns the primary email" do
        get "/api/user/email", headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["email"]).to eq("primary@example.com")
      end
    end

    context "when user has no primary email" do
      it "returns null email" do
        get "/api/user/email", headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["email"]).to be_nil
      end
    end

    context "without authentication" do
      it "returns unauthorized" do
        get "/api/user/email"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "GET /api/user/ics_url" do
    it "returns the ICS calendar URL" do
      get "/api/user/ics_url", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["ics_url"]).to be_present
      expect(json["ics_url"]).to include(user.calendar_token)
    end

    context "without authentication" do
      it "returns unauthorized" do
        get "/api/user/ics_url"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /api/user/gcal" do
    let(:email_address) { "gcal@example.com" }

    context "when email has existing OAuth credentials" do
      before do
        create(:oauth_credential, user: user, email: email_address)
        allow_any_instance_of(GoogleCalendarService).to receive(:create_or_get_course_calendar).and_return("calendar123@google.com")
      end

      it "returns success with calendar_id" do
        post "/api/user/gcal",
             params: { email: email_address }.to_json,
             headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["message"]).to eq("Email already connected")
        expect(json["calendar_id"]).to be_present
      end
    end

    context "when email needs OAuth" do
      it "returns OAuth URL for authorization" do
        post "/api/user/gcal",
             params: { email: "newgcal@example.com" }.to_json,
             headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["message"]).to eq("OAuth required")
        expect(json["email"]).to eq("newgcal@example.com")
        expect(json["oauth_url"]).to be_present
      end
    end

    context "with invalid parameters" do
      it "returns bad request when email is missing" do
        post "/api/user/gcal",
             params: {}.to_json,
             headers: headers

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["error"]).to eq("Email is required")
      end
    end

    context "without authentication" do
      it "returns unauthorized" do
        post "/api/user/gcal",
             params: { email: "test@example.com" }.to_json,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /api/user/gcal/add_email", openapi: false do
    # NOTE: This endpoint requires complex Google Calendar API mocking.
    # The error cases are tested here, success case requires integration test.
    let(:credential) { create(:oauth_credential, user: user, email: "main@example.com") }
    let!(:calendar) { create(:google_calendar, oauth_credential: credential, google_calendar_id: "calendar123@google.com") }

    context "without OAuth credential" do
      it "returns unprocessable entity" do
        user_without_cred = create(:user)
        Flipper.enable(FlipperFlags::V1, user_without_cred)
        token = JsonWebTokenService.encode(user_id: user_without_cred.id)

        post "/api/user/gcal/add_email",
             params: { email: "test@example.com" }.to_json,
             headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unprocessable_content)
        json = response.parsed_body
        expect(json["error"]).to include("complete Google OAuth")
      end
    end

    context "with invalid parameters" do
      it "returns bad request when email is missing" do
        post "/api/user/gcal/add_email",
             params: {}.to_json,
             headers: headers

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["error"]).to eq("Email is required")
      end
    end
  end

  describe "DELETE /api/user/gcal/remove_email", openapi: false do
    # NOTE: This endpoint requires complex Google Calendar API mocking.
    # The error cases are tested here, success case requires integration test.
    let(:credential) { create(:oauth_credential, user: user, email: "main@example.com") }
    let!(:calendar) { create(:google_calendar, oauth_credential: credential, google_calendar_id: "cal123@google.com") }

    context "when email not found" do
      it "returns not found" do
        delete "/api/user/gcal/remove_email",
               params: { email: "nonexistent@example.com" }.to_json,
               headers: headers

        expect(response).to have_http_status(:not_found)
      end
    end

    context "with invalid parameters" do
      it "returns bad request when email is missing" do
        delete "/api/user/gcal/remove_email",
               params: {}.to_json,
               headers: headers

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["error"]).to eq("Email is required")
      end
    end
  end

  describe "POST /api/user/is_processed" do
    let(:term) { create(:term, uid: 202501, year: 2025, season: :spring) }

    context "when user has enrollments for the term" do
      before do
        course = create(:course, term: term)
        create(:enrollment, user: user, course: course, term: term)
      end

      it "returns processed true" do
        post "/api/user/is_processed",
             params: { term_uid: term.uid }.to_json,
             headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["processed"]).to be true
      end
    end

    context "when user has no enrollments for the term" do
      it "returns processed false" do
        post "/api/user/is_processed",
             params: { term_uid: term.uid }.to_json,
             headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["processed"]).to be false
      end
    end

    context "with invalid parameters" do
      it "returns bad request when term_uid is missing" do
        post "/api/user/is_processed",
             params: {}.to_json,
             headers: headers

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["error"]).to eq("term_uid is required")
      end

      it "returns not found when term does not exist" do
        post "/api/user/is_processed",
             params: { term_uid: 999999 }.to_json,
             headers: headers

        expect(response).to have_http_status(:not_found)
        json = response.parsed_body
        expect(json["error"]).to eq("Term not found")
      end
    end
  end

  describe "POST /api/user/processed_events" do
    let(:term) { create(:term, uid: 202501, year: 2025, season: :spring, start_date: Date.current, end_date: Date.current + 90.days) }
    let(:building) { create(:building, name: "Science Building", abbreviation: "SCI") }
    let(:room) { create(:room, building: building, number: "101") }
    let(:faculty) { create(:faculty, first_name: "John", last_name: "Smith", rmp_id: "12345") }
    let(:course) { create(:course, term: term, title: "Computer Science 101", course_number: 101, subject: "CS", schedule_type: :lecture) }
    let!(:meeting_time) do
      create(:meeting_time,
             course: course,
             room: room,
             day_of_week: :monday,
             begin_time: 900,
             end_time: 1050,
             start_date: term.start_date,
             end_date: term.end_date)
    end

    before do
      course.faculties << faculty
      create(:enrollment, user: user, course: course, term: term)
    end

    context "with valid term" do
      it "returns processed events with course details" do
        post "/api/user/processed_events",
             params: { term_uid: term.uid }.to_json,
             headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["classes"]).to be_an(Array)
        expect(json["classes"].length).to eq(1)

        course_data = json["classes"].first
        expect(course_data["title"]).to be_present
        expect(course_data["course_number"]).to eq(101)
        expect(course_data["professor"]).to include("first_name" => "John", "last_name" => "Smith")
        expect(course_data["meeting_times"]).to be_an(Array)
        expect(json).to have_key("notifications_disabled")
      end
    end

    context "with invalid parameters" do
      it "returns bad request when term_uid is missing" do
        post "/api/user/processed_events",
             params: {}.to_json,
             headers: headers

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["error"]).to eq("term_uid is required")
      end

      it "returns not found when term does not exist" do
        post "/api/user/processed_events",
             params: { term_uid: 999999 }.to_json,
             headers: headers

        expect(response).to have_http_status(:not_found)
        json = response.parsed_body
        expect(json["error"]).to eq("Term not found")
      end
    end
  end

  describe "GET /api/user/flag_enabled" do
    context "with valid flag name" do
      it "returns flag status for v1" do
        get "/api/user/flag_enabled",
            params: { flag_name: "v1" },
            headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["feature_name"]).to eq("v1")
        expect(json["is_enabled"]).to be true
      end

      it "returns flag status for disabled flag" do
        get "/api/user/flag_enabled",
            params: { flag_name: "v2" },
            headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["feature_name"]).to eq("v2")
        expect(json["is_enabled"]).to be false
      end
    end

    context "with invalid parameters" do
      it "returns bad request when flag_name is missing" do
        get "/api/user/flag_enabled", headers: headers

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["error"]).to eq("flag_name is required")
      end

      it "returns not found for unknown flag" do
        get "/api/user/flag_enabled",
            params: { flag_name: "unknown_flag" },
            headers: headers

        expect(response).to have_http_status(:not_found)
        json = response.parsed_body
        expect(json["error"]).to eq("Unknown feature flag")
      end
    end
  end
end
