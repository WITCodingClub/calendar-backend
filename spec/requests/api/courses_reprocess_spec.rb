# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Courses#reprocess" do
  let(:user) { create(:user) }
  let(:jwt_token) { JsonWebTokenService.encode(user_id: user.id) }
  let(:headers) { { "Authorization" => "Bearer #{jwt_token}", "Content-Type" => "application/json" } }
  let(:term) { create(:term, uid: 202501, year: 2025, season: :spring) }

  before do
    # Enable the v1 feature flag for API access
    Flipper.enable(FlipperFlags::V1, user)
    # Stub LeopardWebService
    allow(LeopardWebService).to receive_messages(
      get_class_details: {
        associated_term: "Spring 2025",
        subject: "ENG",
        title: "English Composition",
        schedule_type: "Lecture (LEC)",
        section_number: "01",
        credit_hours: 3,
        grade_mode: "Normal"
      },
      get_faculty_meeting_times: {
        "fmt" => []
      }
    )
    # Stub background job
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
  end

  describe "POST /api/courses/reprocess" do
    context "with valid parameters" do
      it "returns success with processed courses" do
        post "/api/courses/reprocess",
             params: {
               courses: [
                 { crn: 12345, term: term.uid, courseNumber: "ENG101", start: Time.zone.today.to_s, end: (Time.zone.today + 90.days).to_s }
               ]
             }.to_json,
             headers: headers

        expect(response).to have_http_status(:ok)

        json = response.parsed_body
        expect(json["ics_url"]).to be_present
        expect(json["removed_enrollments"]).to eq(0)
        expect(json["removed_courses"]).to eq([])
        expect(json["processed_courses"]).to be_an(Array)
        expect(json["processed_courses"].length).to eq(1)
      end

      it "removes old enrollments not in the new course list" do
        # Create existing enrollment
        old_course = create(:course, crn: 11111, term: term, title: "Old Course")
        create(:enrollment, user: user, course: old_course, term: term)

        # Send reprocess with different course
        post "/api/courses/reprocess",
             params: {
               courses: [
                 { crn: 22222, term: term.uid, courseNumber: "ENG102", start: Time.zone.today.to_s, end: (Time.zone.today + 90.days).to_s }
               ]
             }.to_json,
             headers: headers

        expect(response).to have_http_status(:ok)

        json = response.parsed_body
        expect(json["removed_enrollments"]).to eq(1)
        expect(json["removed_courses"]).to include(hash_including("crn" => 11111))
      end

      it "accepts courses in _json format (array body)" do
        post "/api/courses/reprocess",
             params: [
               { crn: 12345, term: term.uid, courseNumber: "ENG101", start: Time.zone.today.to_s, end: (Time.zone.today + 90.days).to_s }
             ].to_json,
             headers: headers

        expect(response).to have_http_status(:ok)
      end
    end

    context "with invalid parameters" do
      it "returns bad request when no courses provided" do
        post "/api/courses/reprocess",
             params: { courses: nil }.to_json,
             headers: headers

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["error"]).to eq("No courses provided")
      end

      it "returns bad request when courses is empty" do
        post "/api/courses/reprocess",
             params: { courses: [] }.to_json,
             headers: headers

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["error"]).to eq("No courses provided")
      end

      it "returns bad request when courses are from different terms" do
        create(:term, uid: 202502, year: 2025, season: :summer)

        post "/api/courses/reprocess",
             params: {
               courses: [
                 { crn: 12345, term: 202501 },
                 { crn: 67890, term: 202502 }
               ]
             }.to_json,
             headers: headers

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["error"]).to include("same term")
      end

      it "returns bad request when term does not exist" do
        post "/api/courses/reprocess",
             params: {
               courses: [
                 { crn: 12345, term: 999999 }
               ]
             }.to_json,
             headers: headers

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["error"]).to include("not found")
      end
    end

    context "without authentication" do
      it "returns unauthorized" do
        post "/api/courses/reprocess",
             params: {
               courses: [
                 { crn: 12345, term: term.uid }
               ]
             }.to_json,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "integration scenario" do
      it "handles section change scenario" do
        # User initially enrolled in ENG-101 Section A (CRN: 11111)
        old_section = create(:course, crn: 11111, term: term, title: "English Composition Section A", section_number: "A")
        create(:enrollment, user: user, course: old_section, term: term)

        # User also enrolled in MATH-102 (CRN: 22222) - this stays
        math_course = create(:course, crn: 22222, term: term, title: "Math Course")
        create(:enrollment, user: user, course: math_course, term: term)

        expect(user.enrollments.count).to eq(2)

        # User switches to ENG-101 Section B (CRN: 33333) in LeopardWeb
        # Frontend sends the new course list
        post "/api/courses/reprocess",
             params: {
               courses: [
                 { crn: 33333, term: term.uid, courseNumber: "ENG101", start: Time.zone.today.to_s, end: (Time.zone.today + 90.days).to_s },
                 { crn: 22222, term: term.uid, courseNumber: "MATH102", start: Time.zone.today.to_s, end: (Time.zone.today + 90.days).to_s }
               ]
             }.to_json,
             headers: headers

        expect(response).to have_http_status(:ok)

        json = response.parsed_body
        expect(json["removed_enrollments"]).to eq(1)
        expect(json["removed_courses"]).to include(hash_including("crn" => 11111))

        # Verify user's enrollments are updated
        user.reload
        expect(user.enrollments.count).to eq(2)
        expect(user.courses.pluck(:crn)).to contain_exactly(22222, 33333)
        expect(user.courses.pluck(:crn)).not_to include(11111)
      end
    end
  end
end
