# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::CalendarPreferences actions", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }

  def json = response.parsed_body

  before { allow(CourseCalendars::SyncJob).to receive(:perform_later) }

  describe "GET /api/calendar_preferences" do
    it "groups every preference of the user by scope" do
      create(:calendar_preference, user: user, color_id: "#112233")
      create(:calendar_preference, :uni_cal_global, user: user)
      create(:calendar_preference, :for_event_type, user: user, event_type: "lecture")
      create(:calendar_preference, :uni_cal_category, user: user, event_type: "holiday")
      create(:calendar_preference, user: create(:user), color_id: "#445566")

      get "/api/calendar_preferences", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json["global"]["color_id"]).to eq("#112233")
      expect(json["uni_cal_global"]).to be_present
      expect(json["event_types"].keys).to eq([ "lecture" ])
      expect(json["uni_cal_categories"].keys).to eq([ "holiday" ])
    end

    it "returns empty groups for a user with no preferences" do
      get "/api/calendar_preferences", headers: headers

      expect(json).to eq("global" => nil, "uni_cal_global" => nil, "event_types" => {}, "uni_cal_categories" => {})
    end
  end

  describe "GET /api/calendar_preferences/:id" do
    it "returns a saved preference of an event type" do
      create(:calendar_preference, :for_event_type, user: user, event_type: "lecture", title_template: "{{title}}")

      get "/api/calendar_preferences/lecture", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json["title_template"]).to eq("{{title}}")
    end

    it "returns the global preference, and the category preference by its scope" do
      create(:calendar_preference, user: user, color_id: "#112233")
      create(:calendar_preference, :uni_cal_category, user: user, event_type: "holiday", color_id: "#445566")

      get "/api/calendar_preferences/global", headers: headers
      expect(json["color_id"]).to eq("#112233")

      get "/api/calendar_preferences/uni_cal:holiday", headers: headers
      expect(json["color_id"]).to eq("#445566")
    end

    it "does not return the preference of another user" do
      create(:calendar_preference, user: create(:user), color_id: "#778899")

      get "/api/calendar_preferences/global", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json["color_id"]).to be_nil
    end
  end

  describe "PATCH /api/calendar_preferences/:id" do
    it "creates the preference of an event type and queues a forced sync" do
      patch "/api/calendar_preferences/lecture",
            params: { calendar_preference: { title_template: "{{course_code}}", visibility: "private" } },
            headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(user.calendar_preferences.find_by(scope: :event_type, event_type: "lecture").title_template).to eq("{{course_code}}")
      expect(CourseCalendars::SyncJob).to have_received(:perform_later).with(user, force: true)
    end

    it "answers UNPROCESSABLE_CONTENT with the messages for an invalid color" do
      patch "/api/calendar_preferences/global",
            params: { calendar_preference: { color_id: "not-a-color" } }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("VALIDATION_FAILED")
      expect(json["errors"]).to be_an(Array).and be_present
      expect(CourseCalendars::SyncJob).not_to have_received(:perform_later)
    end

    it "answers VALIDATION_FAILED for a template with a disallowed variable" do
      patch "/api/calendar_preferences/global",
            params: { calendar_preference: { title_template: "{{secret}}" } }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to include("Disallowed variables")
    end

    it "answers VALIDATION_FAILED for an unknown university category" do
      patch "/api/calendar_preferences/uni_cal:bogus",
            params: { calendar_preference: { visibility: "private" } }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("VALIDATION_FAILED")
    end

    it "answers BAD_REQUEST when the calendar_preference key is missing" do
      patch "/api/calendar_preferences/global", params: {}, headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(json["code"]).to eq("BAD_REQUEST")
    end

    it "does not touch the preference of another user" do
      other = create(:calendar_preference, user: create(:user), color_id: "#778899")

      patch "/api/calendar_preferences/global",
            params: { calendar_preference: { color_id: "#112233" } }, headers: headers, as: :json

      expect(other.reload.color_id).to eq("#778899")
      expect(user.calendar_preferences.find_by(scope: :global).color_id).to eq("#112233")
    end
  end

  describe "DELETE /api/calendar_preferences/:id" do
    it "deletes the preference and queues a forced sync" do
      pref = create(:calendar_preference, :for_event_type, user: user, event_type: "lecture")

      delete "/api/calendar_preferences/lecture", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(CalendarPreference.exists?(pref.id)).to be(false)
      expect(CourseCalendars::SyncJob).to have_received(:perform_later).with(user, force: true)
    end

    it "keeps the preference of another user" do
      other = create(:calendar_preference, user: create(:user))

      delete "/api/calendar_preferences/global", headers: headers

      expect(CalendarPreference.exists?(other.id)).to be(true)
    end
  end

  describe "POST /api/calendar_preferences/preview" do
    let(:course)       { create(:course, title: "Intro to Testing") }
    let(:meeting_time) { create(:course_meeting_time, course: course) }

    def preview(params) = post("/api/calendar_preferences/preview", params: params, headers: headers, as: :json)

    it "asks for a template" do
      preview(meeting_time_id: meeting_time.id)

      expect(response).to have_http_status(:bad_request)
      expect(json).to eq("error" => "Template is required", "code" => "BAD_REQUEST")
    end

    it "asks for a meeting time" do
      preview(template: "{{title}}")

      expect(response).to have_http_status(:bad_request)
      expect(json).to eq("error" => "meeting_time_id is required", "code" => "BAD_REQUEST")
    end

    it "answers NOT_FOUND for an unknown numeric id" do
      preview(template: "{{title}}", meeting_time_id: 0)

      expect(response).to have_http_status(:not_found)
      expect(json).to eq("error" => "Meeting time not found", "code" => "NOT_FOUND")
    end

    it "answers NOT_FOUND for an unknown public id" do
      preview(template: "{{title}}", meeting_time_id: "cmt_unknown")

      expect(response).to have_http_status(:not_found)
    end

    it "answers NOT_FOUND for a meeting time the user is not enrolled in" do
      preview(template: "{{title}}", meeting_time_id: meeting_time.id)

      expect(response).to have_http_status(:not_found)
      expect(json["error"]).to eq("Meeting time not found")
    end

    it "renders the template for an enrolled meeting time by numeric id" do
      create(:enrollment, user: user, course: course)

      preview(template: "{{title}} {{day}}", meeting_time_id: meeting_time.id)

      expect(response).to have_http_status(:ok)
      expect(json).to eq("rendered" => "Intro to Testing Monday", "valid" => true)
    end

    it "renders the template for an enrolled meeting time by public id" do
      create(:enrollment, user: user, course: course)

      preview(template: "{{title}}", meeting_time_id: meeting_time.public_id)

      expect(response).to have_http_status(:ok)
      expect(json["rendered"]).to eq("Intro to Testing")
    end

    it "answers VALIDATION_FAILED with valid false for a bad template" do
      create(:enrollment, user: user, course: course)

      preview(template: "{{secret}}", meeting_time_id: meeting_time.id)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("valid" => false, "code" => "VALIDATION_FAILED")
      expect(json["error"]).to include("Disallowed variables")
    end

    it "answers VALIDATION_FAILED for a template with a syntax error" do
      create(:enrollment, user: user, course: course)

      preview(template: "{{ title", meeting_time_id: meeting_time.id)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to start_with("Syntax error")
    end
  end
end
