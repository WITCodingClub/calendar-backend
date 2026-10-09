# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::UniversityCalendarEvents", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }

  def json = response.parsed_body

  def event(**attrs)
    create(:university_calendar_event, start_time: 1.week.from_now, end_time: 1.week.from_now + 1.hour, **attrs)
  end

  describe "GET /api/university_calendar_events" do
    it "lists upcoming events in start order with pagination meta" do
      later   = event(summary: "Later", start_time: 3.weeks.from_now, end_time: 3.weeks.from_now + 1.hour)
      sooner  = event(summary: "Sooner", start_time: 2.days.from_now, end_time: 2.days.from_now + 1.hour)
      create(:university_calendar_event, summary: "Past", start_time: 3.days.ago, end_time: 3.days.ago + 1.hour)

      get "/api/university_calendar_events", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json["events"].pluck("summary")).to eq([ sooner.summary, later.summary ])
      expect(json["meta"]).to include("current_page" => 1, "total_count" => 2, "per_page" => 25)
    end

    it "paginates with per_page and page" do
      event(summary: "A", start_time: 1.day.from_now, end_time: 1.day.from_now + 1.hour)
      event(summary: "B", start_time: 2.days.from_now, end_time: 2.days.from_now + 1.hour)

      get "/api/university_calendar_events", params: { per_page: 1, page: 2 }, headers: headers

      expect(json["events"].pluck("summary")).to eq([ "B" ])
      expect(json["meta"]).to include("current_page" => 2, "total_pages" => 2, "per_page" => 1)
    end

    it "filters by one category" do
      event(summary: "Holiday", category: "holiday")
      event(summary: "Finals", category: "finals")

      get "/api/university_calendar_events", params: { category: "holiday" }, headers: headers

      expect(json["events"].pluck("summary")).to eq([ "Holiday" ])
    end

    it "filters by a comma separated list of categories" do
      event(summary: "Holiday", category: "holiday")
      event(summary: "Finals", category: "finals")
      event(summary: "Deadline", category: "deadline")

      get "/api/university_calendar_events", params: { categories: "holiday,finals" }, headers: headers

      expect(json["events"].pluck("summary")).to contain_exactly("Holiday", "Finals")
    end

    it "filters by an array of categories" do
      event(summary: "Holiday", category: "holiday")
      event(summary: "Finals", category: "finals")

      get "/api/university_calendar_events", params: { categories: [ "finals" ] }, headers: headers

      expect(json["events"].pluck("summary")).to eq([ "Finals" ])
    end

    it "filters by a date range" do
      inside  = event(summary: "Inside", start_time: Time.zone.local(2099, 1, 10, 9), end_time: Time.zone.local(2099, 1, 10, 10))
      event(summary: "Outside", start_time: Time.zone.local(2099, 3, 10, 9), end_time: Time.zone.local(2099, 3, 10, 10))

      get "/api/university_calendar_events", params: { start_date: "2099-01-01", end_date: "2099-01-31" }, headers: headers

      expect(json["events"].pluck("summary")).to eq([ inside.summary ])
    end

    it "answers BAD_REQUEST for a date that is not ISO 8601" do
      get "/api/university_calendar_events", params: { start_date: "01/02/2099", end_date: "2099-01-31" }, headers: headers

      expect(response).to have_http_status(:bad_request)
      expect(json).to eq("error" => "Invalid start_date: use ISO 8601 format (YYYY-MM-DD)", "code" => "BAD_REQUEST")
    end

    it "filters by term public id" do
      term = create(:term)
      event(summary: "In term", term: term)
      event(summary: "No term")

      get "/api/university_calendar_events", params: { term_id: term.public_id }, headers: headers

      expect(json["events"].pluck("summary")).to eq([ "In term" ])
    end

    it "ignores an unknown term id" do
      event(summary: "Any")

      get "/api/university_calendar_events", params: { term_id: "term_unknown" }, headers: headers

      expect(json["events"].size).to eq(1)
    end
  end

  describe "GET /api/university_calendar_events/:id" do
    it "returns one event" do
      record = event(summary: "Commencement")

      get "/api/university_calendar_events/#{record.public_id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json["event"]["summary"]).to eq("Commencement")
    end

    it "answers NOT_FOUND for an unknown id" do
      get "/api/university_calendar_events/uce_unknown", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(json).to eq("error" => "UniversityCalendarEvent not found", "code" => "NOT_FOUND")
    end
  end

  describe "GET /api/university_calendar_events/categories" do
    it "counts events for every syncable category" do
      event(category: "holiday")
      event(category: "holiday")

      get "/api/university_calendar_events/categories", headers: headers

      categories = json["categories"]
      expect(categories.pluck("id")).to eq(UniversityCalendarEvent::SYNCABLE_CATEGORIES)
      expect(categories.find { |c| c["id"] == "holiday" }).to eq("id" => "holiday", "name" => "Holiday", "count" => 2)
      expect(categories.find { |c| c["id"] == "finals" }["count"]).to eq(0)
    end
  end

  describe "GET /api/university_calendar_events/holidays" do
    it "lists only upcoming holidays" do
      holiday = event(summary: "Break", category: "holiday")
      event(summary: "Finals", category: "finals")
      create(:university_calendar_event, category: "holiday", start_time: 2.days.ago, end_time: 2.days.ago + 1.hour)

      get "/api/university_calendar_events/holidays", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json["holidays"].pluck("summary")).to eq([ holiday.summary ])
    end

    it "filters by term and date range" do
      term = create(:term)
      inside = event(summary: "Inside", category: "holiday", term: term,
                     start_time: Time.zone.local(2099, 1, 10, 9), end_time: Time.zone.local(2099, 1, 10, 10))
      event(summary: "Other term", category: "holiday",
            start_time: Time.zone.local(2099, 1, 11, 9), end_time: Time.zone.local(2099, 1, 11, 10))
      event(summary: "Outside", category: "holiday", term: term,
            start_time: Time.zone.local(2099, 6, 10, 9), end_time: Time.zone.local(2099, 6, 10, 10))

      get "/api/university_calendar_events/holidays",
          params: { term_id: term.public_id, start_date: "2099-01-01", end_date: "2099-01-31" }, headers: headers

      expect(json["holidays"].pluck("summary")).to eq([ inside.summary ])
    end

    it "ignores an unknown term id" do
      event(category: "holiday")

      get "/api/university_calendar_events/holidays", params: { term_id: "term_unknown" }, headers: headers

      expect(json["holidays"].size).to eq(1)
    end

    it "answers BAD_REQUEST for a bad date" do
      get "/api/university_calendar_events/holidays", params: { start_date: "2099-01-01", end_date: "nope" }, headers: headers

      expect(response).to have_http_status(:bad_request)
      expect(json["code"]).to eq("BAD_REQUEST")
      expect(json["error"]).to start_with("Invalid end_date")
    end
  end

  describe "POST /api/university_calendar_events/sync" do
    before { allow(UniversityCalendar::SyncJob).to receive(:perform_later) }

    it "queues the sync for an admin" do
      admin = create(:user, :admin)

      post "/api/university_calendar_events/sync", headers: auth_headers_for(admin)

      expect(response).to have_http_status(:ok)
      expect(json).to eq("message" => "University calendar sync queued")
      expect(UniversityCalendar::SyncJob).to have_received(:perform_later)
    end

    it "answers FORBIDDEN for a regular user and queues nothing" do
      post "/api/university_calendar_events/sync", headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(json["code"]).to eq("FORBIDDEN")
      expect(UniversityCalendar::SyncJob).not_to have_received(:perform_later)
    end
  end
end
