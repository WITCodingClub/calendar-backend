# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Reports", type: :request do
  describe "GET /reports/meeting_times" do
    let!(:fall_term)   { Term.create!(uid: 202710, year: 2026, season: :fall) }
    let!(:spring_term) { Term.create!(uid: 202620, year: 2026, season: :spring) }

    let!(:fall_course) do
      fall_term.courses.create!(
        crn: 12345, subject: "Computer Science", course_number: 3100,
        section_number: "01", title: "Algorithms", schedule_type: :lecture,
        seats_capacity: 30, seats_available: 5,
        start_date: Date.new(2026, 9, 8), end_date: Date.new(2026, 12, 15)
      )
    end

    let!(:spring_course) do
      spring_term.courses.create!(
        crn: 54321, subject: "Mathematics", course_number: 2025,
        section_number: "02", title: "Linear Algebra", schedule_type: :laboratory,
        seats_capacity: 24, seats_available: 0,
        start_date: Date.new(2026, 1, 12), end_date: Date.new(2026, 4, 20)
      )
    end

    let!(:fall_meeting) do
      fall_course.meeting_times.create!(
        begin_time: 900, end_time: 1050, day_of_week: :monday,
        meeting_schedule_type: :lecture, meeting_type: :class_meeting,
        start_date: fall_course.start_date, end_date: fall_course.end_date
      )
    end

    let!(:spring_meeting) do
      spring_course.meeting_times.create!(
        begin_time: 1350, end_time: 1550, day_of_week: :thursday,
        meeting_schedule_type: :laboratory, meeting_type: :class_meeting,
        start_date: spring_course.start_date, end_date: spring_course.end_date
      )
    end

    it "returns a CSV of all meeting times" do
      get "/reports/meeting_times"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")

      csv = CSV.parse(response.body, headers: true)
      expect(csv.length).to eq(2)

      row = csv.find { |r| r["crn"] == "12345" }
      expect(row.to_h).to include(
        "term_uid"       => "202710",
        "term"           => "Fall 2026",
        "subject"        => "Computer Science",
        "course_number"  => "3100",
        "section_number" => "01",
        "title"          => "Algorithms",
        "schedule_type"  => "lecture",
        "status"         => "active",
        "seats_capacity" => "30",
        "seats_available" => "5",
        "day"            => "monday",
        "day_of_week"    => "1",
        "begin_time"     => "09:00",
        "end_time"       => "10:50",
        "meeting_type"   => "lecture"
      )
    end

    it "filters by term_uid" do
      get "/reports/meeting_times", params: { term_uid: 202620 }

      csv = CSV.parse(response.body, headers: true)
      expect(csv.length).to eq(1)
      expect(csv.first["crn"]).to eq("54321")
      expect(csv.first["term"]).to eq("Spring 2026")
      expect(csv.first["begin_time"]).to eq("13:50")
    end

    it "returns only headers when the term has no data" do
      get "/reports/meeting_times", params: { term_uid: 999999 }

      expect(response).to have_http_status(:ok)
      csv = CSV.parse(response.body, headers: true)
      expect(csv.length).to eq(0)
    end

    it "serves non-browser clients such as Power BI and curl" do
      get "/reports/meeting_times", headers: { "User-Agent" => "curl/8.7.1" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
      expect(CSV.parse(response.body, headers: true).length).to eq(2)
    end

    it "sets public cache headers" do
      get "/reports/meeting_times"

      expect(response.headers["Cache-Control"]).to include("public")
      expect(response.headers["Cache-Control"]).to include("max-age=3600")
    end
  end
end
