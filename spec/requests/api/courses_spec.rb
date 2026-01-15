# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Courses#process_courses" do
  let(:user) { create(:user) }
  let(:jwt_token) { JsonWebTokenService.encode(user_id: user.id) }
  let(:headers) { { "Authorization" => "Bearer #{jwt_token}", "Content-Type" => "application/json" } }
  let(:term) { create(:term, uid: 202501, year: 2025, season: :spring) }

  before do
    Flipper.enable(FlipperFlags::V1, user)
    allow(LeopardWebService).to receive_messages(
      get_class_details: {
        associated_term: "Spring 2025",
        subject: "CS",
        title: "Introduction to Computer Science",
        schedule_type: "Lecture (LEC)",
        section_number: "01",
        credit_hours: 3,
        grade_mode: "Normal"
      },
      get_faculty_meeting_times: {
        "fmt" => []
      }
    )
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
  end

  describe "POST /api/process_courses" do
    context "with valid parameters" do
      it "processes courses and returns ICS URL" do
        post "/api/process_courses",
             params: {
               courses: [
                 { crn: 12345, term: term.uid, courseNumber: "CS101", start: Time.zone.today.to_s, end: (Time.zone.today + 90.days).to_s }
               ]
             }.to_json,
             headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["user_pub"]).to eq(user.public_id)
        expect(json["ics_url"]).to be_present
      end

      it "creates enrollments for the user" do
        expect {
          post "/api/process_courses",
               params: {
                 courses: [
                   { crn: 12345, term: term.uid, courseNumber: "CS101", start: Time.zone.today.to_s, end: (Time.zone.today + 90.days).to_s }
                 ]
               }.to_json,
               headers: headers
        }.to change(Enrollment, :count).by(1)

        expect(response).to have_http_status(:ok)
      end

      it "accepts courses in _json format (array body)" do
        post "/api/process_courses",
             params: [
               { crn: 12345, term: term.uid, courseNumber: "CS101", start: Time.zone.today.to_s, end: (Time.zone.today + 90.days).to_s }
             ].to_json,
             headers: headers

        expect(response).to have_http_status(:ok)
      end

      it "processes multiple courses at once" do
        post "/api/process_courses",
             params: {
               courses: [
                 { crn: 12345, term: term.uid, courseNumber: "CS101", start: Time.zone.today.to_s, end: (Time.zone.today + 90.days).to_s },
                 { crn: 12346, term: term.uid, courseNumber: "CS102", start: Time.zone.today.to_s, end: (Time.zone.today + 90.days).to_s }
               ]
             }.to_json,
             headers: headers

        expect(response).to have_http_status(:ok)
      end
    end

    context "with invalid parameters" do
      it "returns bad request when no courses provided" do
        post "/api/process_courses",
             params: { courses: nil }.to_json,
             headers: headers

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["error"]).to eq("No courses provided")
      end

      it "returns bad request when courses is empty array" do
        post "/api/process_courses",
             params: { courses: [] }.to_json,
             headers: headers

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["error"]).to eq("No courses provided")
      end
    end

    context "without authentication" do
      it "returns unauthorized" do
        post "/api/process_courses",
             params: {
               courses: [
                 { crn: 12345, term: term.uid }
               ]
             }.to_json,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
