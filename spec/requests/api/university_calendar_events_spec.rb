# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::UniversityCalendarEvents" do
  let(:user) { create(:user) }
  let(:jwt_token) { JsonWebTokenService.encode(user_id: user.id) }
  let(:headers) { { "Authorization" => "Bearer #{jwt_token}" } }

  before do
    # Enable the v1 feature flag for API access
    Flipper.enable(FlipperFlags::V1, user)
  end

  describe "GET /api/university_calendar_events" do
    let!(:holiday) do
      create(:university_calendar_event,
             category: "holiday",
             summary: "Labor Day",
             start_time: 1.week.from_now.beginning_of_day,
             end_time: 1.week.from_now.end_of_day)
    end

    let!(:campus_event) do
      create(:university_calendar_event,
             category: "campus_event",
             summary: "Spring Concert",
             start_time: 2.weeks.from_now.beginning_of_day,
             end_time: 2.weeks.from_now.end_of_day)
    end

    let!(:past_event) do
      create(:university_calendar_event, :past,
             summary: "Past Event")
    end

    it "returns upcoming events" do
      get "/api/university_calendar_events", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body

      expect(json["events"].length).to eq(2)
      expect(json["events"].pluck("summary")).to include("Labor Day", "Spring Concert")
      expect(json["events"].pluck("summary")).not_to include("Past Event")
    end

    it "filters by category" do
      get "/api/university_calendar_events", params: { category: "holiday" }, headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body

      expect(json["events"].length).to eq(1)
      expect(json["events"].first["summary"]).to eq("Labor Day")
    end

    it "filters by multiple categories" do
      get "/api/university_calendar_events", params: { categories: "holiday,campus_event" }, headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body

      expect(json["events"].length).to eq(2)
    end

    it "filters by date range" do
      get "/api/university_calendar_events",
          params: {
            start_date: 1.week.from_now.to_date.to_s,
            end_date: 1.week.from_now.to_date.to_s
          },
          headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body

      expect(json["events"].length).to eq(1)
      expect(json["events"].first["summary"]).to eq("Labor Day")
    end

    it "includes pagination meta" do
      get "/api/university_calendar_events", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body

      expect(json["meta"]).to include(
        "current_page" => 1,
        "total_count"  => 2
      )
    end
  end

  describe "GET /api/university_calendar_events/:id" do
    let!(:event) do
      create(:university_calendar_event,
             summary: "Test Event",
             description: "A description",
             location: "Main Campus",
             category: "academic")
    end

    it "returns the event details" do
      get "/api/university_calendar_events/#{event.public_id}", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body

      expect(json["event"]["summary"]).to eq("Test Event")
      expect(json["event"]["description"]).to eq("A description")
      expect(json["event"]["location"]).to eq("Main Campus")
      expect(json["event"]["category"]).to eq("academic")
    end

    it "returns 404 for non-existent event" do
      get "/api/university_calendar_events/uce_nonexistent", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/university_calendar_events/categories" do
    before do
      create(:university_calendar_event, category: "holiday")
      create(:university_calendar_event, category: "holiday")
      create(:university_calendar_event, category: "academic")
      create(:university_calendar_event, category: "campus_event")
    end

    it "returns all categories with counts" do
      get "/api/university_calendar_events/categories", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body

      expect(json["categories"]).to be_an(Array)
      expect(json["categories"].pluck("id")).to include("holiday", "academic", "campus_event")

      holiday_cat = json["categories"].find { |c| c["id"] == "holiday" }
      expect(holiday_cat["count"]).to eq(2)
    end
  end

  describe "GET /api/university_calendar_events/holidays" do
    let(:term) { create(:term, year: 2024, season: :fall) }

    let!(:labor_day) do
      create(:university_calendar_event,
             category: "holiday",
             summary: "Labor Day",
             start_time: 1.week.from_now.beginning_of_day,
             end_time: 1.week.from_now.end_of_day)
    end

    let!(:thanksgiving) do
      create(:university_calendar_event,
             category: "holiday",
             summary: "Thanksgiving",
             term: term,
             start_time: 2.weeks.from_now.beginning_of_day,
             end_time: 2.weeks.from_now.end_of_day)
    end

    let!(:non_holiday) do
      create(:university_calendar_event,
             category: "campus_event",
             summary: "Concert",
             start_time: 1.week.from_now.beginning_of_day,
             end_time: 1.week.from_now.end_of_day)
    end

    it "returns only holidays" do
      get "/api/university_calendar_events/holidays", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body

      expect(json["holidays"].length).to eq(2)
      expect(json["holidays"].pluck("summary")).to include("Labor Day", "Thanksgiving")
      expect(json["holidays"].pluck("summary")).not_to include("Concert")
    end

    it "filters by term" do
      get "/api/university_calendar_events/holidays",
          params: { term_id: term.public_id },
          headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body

      expect(json["holidays"].length).to eq(1)
      expect(json["holidays"].first["summary"]).to eq("Thanksgiving")
    end
  end

  describe "POST /api/university_calendar_events/sync" do
    context "as a regular user" do
      it "returns unauthorized" do
        post "/api/university_calendar_events/sync", headers: headers

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "as an admin" do
      let(:admin) { create(:user, :admin) }
      let(:admin_jwt_token) { JsonWebTokenService.encode(user_id: admin.id) }
      let(:admin_headers) { { "Authorization" => "Bearer #{admin_jwt_token}" } }

      before do
        Flipper.enable(FlipperFlags::V1, admin)
      end

      it "queues a sync job" do
        expect {
          post "/api/university_calendar_events/sync", headers: admin_headers
        }.to have_enqueued_job(UniversityCalendarSyncJob)

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["message"]).to eq("University calendar sync queued")
      end
    end
  end
end
