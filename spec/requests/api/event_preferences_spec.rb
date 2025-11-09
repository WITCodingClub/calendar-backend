# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::EventPreferences", type: :request do
  let(:user) { create(:user) }
  let!(:term) { create(:term) }
  let!(:building) { create(:building, name: "Wentworth Hall") }
  let!(:room) { create(:room, building: building, number: "306") }
  let!(:faculty) { create(:faculty, first_name: "Jane", last_name: "Smith", email: "jane.smith@witcc.edu") }
  let!(:course) do
    create(:course,
           term: term,
           title: "Computer Science I",
           subject: "COMP",
           course_number: "101",
           section_number: "01",
           crn: "12345",
           schedule_type: "laboratory",
           faculties: [faculty])
  end
  let!(:meeting_time) do
    create(:meeting_time,
           course: course,
           room: room,
           day_of_week: "monday",
           begin_time: 900,
           end_time: 1030)
  end
  let(:jwt_token) { JsonWebTokenService.encode(user_id: user.id) }
  let(:headers) { { "Authorization" => "Bearer #{jwt_token}" } }

  before do
    # Enable the v1 feature flag for API access
    Flipper.enable(FlipperFlags::V1, user)
  end


  describe "GET /api/meeting_times/:meeting_time_id/preference" do
    it "includes templates object with all template variable values" do
      get "/api/meeting_times/#{meeting_time.id}/preference", headers: headers

      expect(response).to have_http_status(:ok)

      json = response.parsed_body
      expect(json).to have_key("templates")

      templates = json["templates"]
      expect(templates).to include(
        "title"          => "Computer Science I",
        "course_code"    => "COMP-101-01",
        "subject"        => "COMP",
        "course_number"  => 101, # Integer from database
        "section_number" => "01",
        "crn"            => 12345, # Integer from database
        "room"           => 306, # Integer from database
        "building"       => "Wentworth Hall",
        "location"       => "Wentworth Hall - 306",
        "faculty"        => "Jane Smith",
        "faculty_email"  => "jane.smith@witcc.edu",
        "all_faculty"    => "Jane Smith",
        "start_time"     => "9:00 AM",
        "end_time"       => "10:30 AM",
        "day"            => "Monday",
        "day_abbr"       => "Mon",
        "schedule_type"  => "laboratory"
      )
    end

    it "still includes all other response fields" do
      get "/api/meeting_times/#{meeting_time.id}/preference", headers: headers

      expect(response).to have_http_status(:ok)

      json = response.parsed_body
      expect(json).to have_key("individual_preference")
      expect(json).to have_key("resolved")
      expect(json).to have_key("sources")
      expect(json).to have_key("preview")
    end
  end

  describe "PUT /api/meeting_times/:meeting_time_id/preference" do
    it "includes templates object in update response" do
      put "/api/meeting_times/#{meeting_time.id}/preference",
          params: {
            event_preference: {
              color_id: 5
            }
          },
          headers: headers,
          as: :json

      expect(response).to have_http_status(:ok)

      json = response.parsed_body
      expect(json).to have_key("templates")
      expect(json["templates"]).to include(
        "title"       => "Computer Science I",
        "course_code" => "COMP-101-01"
      )
    end
  end
end
