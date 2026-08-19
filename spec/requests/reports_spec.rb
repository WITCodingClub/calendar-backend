# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Reports", type: :request do
  describe "GET /reports/meeting_times" do
    let!(:fall_term)   { Term.create!(uid: 202710, year: 2026, season: :fall) }
    let!(:spring_term) { Term.create!(uid: 202620, year: 2026, season: :spring) }

    let!(:annex)   { Building.create!(abbreviation: "ANX", name: "Annex") }
    let!(:dobbs)    { Building.create!(abbreviation: "DOB", name: "Dobbs Hall") }
    let!(:room_305) { annex.rooms.create!(number: "305") }
    let!(:room_5)   { dobbs.rooms.create!(number: "5") }

    let!(:fall_course) do
      fall_term.courses.create!(
        crn: 12345, subject: "Computer Science", course_number: 3100,
        section_number: "01", title: "Algorithms", schedule_type: :lecture,
        seats_capacity: 30, seats_available: 5, credit_hours: 4,
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

    let!(:lovelace) do
      Faculty.create!(first_name: "Ada", last_name: "Lovelace",
                      display_name: "Ada Lovelace", email: "lovelacea@wit.edu")
    end

    before do
      fall_meeting.rooms << room_305
      fall_course.faculties << lovelace
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
        "credit_hours"   => "4",
        "faculty"        => "Ada Lovelace",
        "enrollment_current" => "25",
        "seats_capacity" => "30",
        "seats_available" => "5",
        "day"            => "monday",
        "day_of_week"    => "1",
        "begin_time"     => "09:00",
        "end_time"       => "10:50",
        "meeting_type"   => "lecture",
        "building"       => "ANX",
        "building_name"  => "Annex",
        "room_number"    => "305",
        "room"           => "ANX 305"
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

    it "collapses duplicate meeting time rows into one" do
      # Ingest copies the room assignment too, so the duplicate is identical
      # across every column the report selects.
      duplicate = fall_course.meeting_times.create!(
        begin_time: 900, end_time: 1050, day_of_week: :monday,
        meeting_schedule_type: :lecture, meeting_type: :class_meeting,
        start_date: fall_course.start_date, end_date: fall_course.end_date
      )
      duplicate.rooms << room_305

      get "/reports/meeting_times", params: { term_uid: 202710 }

      csv = CSV.parse(response.body, headers: true)
      expect(csv.length).to eq(1)
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

    it "keeps meeting times that have no room assigned" do
      get "/reports/meeting_times", params: { term_uid: 202620 }

      csv = CSV.parse(response.body, headers: true)
      expect(csv.length).to eq(1)
      expect(csv.first["crn"]).to eq("54321")
      expect(csv.first["building"]).to be_nil
      expect(csv.first["room"]).to be_nil
    end

    it "emits one row per room when a meeting time is booked into two rooms" do
      fall_meeting.rooms << room_5

      get "/reports/meeting_times", params: { term_uid: 202710 }

      csv = CSV.parse(response.body, headers: true)
      expect(csv.length).to eq(2)
      expect(csv.map { |r| r["room"] }).to contain_exactly("ANX 305", "DOB 005")
      expect(csv.map { |r| r["crn"] }.uniq).to eq([ "12345" ])
    end

    it "pads purely numeric room numbers to three digits" do
      spring_meeting.rooms << room_5

      get "/reports/meeting_times", params: { term_uid: 202620 }

      csv = CSV.parse(response.body, headers: true)
      expect(csv.first["room_number"]).to eq("005")
      expect(csv.first["room"]).to eq("DOB 005")
    end

    it "joins team-taught faculty into one column without multiplying rows" do
      babbage = Faculty.create!(first_name: "Charles", last_name: "Babbage",
                                display_name: "Charles Babbage", email: "babbagec@wit.edu")
      fall_course.faculties << babbage

      get "/reports/meeting_times", params: { term_uid: 202710 }

      csv = CSV.parse(response.body, headers: true)
      expect(csv.length).to eq(1)
      expect(csv.first["faculty"]).to eq("Charles Babbage, Ada Lovelace")
    end

    it "leaves enrollment_current blank when seat counts are missing" do
      spring_course.update!(seats_capacity: nil, seats_available: nil)

      get "/reports/meeting_times", params: { term_uid: 202620 }

      csv = CSV.parse(response.body, headers: true)
      expect(csv.first["enrollment_current"]).to be_nil
    end

    it "sets public cache headers" do
      get "/reports/meeting_times"

      expect(response.headers["Cache-Control"]).to include("public")
      expect(response.headers["Cache-Control"]).to include("max-age=3600")
    end
  end

  describe "GET /reports/terms" do
    let!(:fall_term)   { Term.create!(uid: 202710, year: 2026, season: :fall) }
    let!(:spring_term) { Term.create!(uid: 202620, year: 2026, season: :spring) }
    let!(:empty_term)  { Term.create!(uid: 202730, year: 2026, season: :summer) }

    before do
      [ fall_term, spring_term ].each_with_index do |term, i|
        course = term.courses.create!(
          crn: 10_000 + i, subject: "CS", course_number: 1000, section_number: "01",
          title: "Intro", schedule_type: :lecture,
          start_date: Date.new(2026, 1, 12), end_date: Date.new(2026, 4, 20)
        )
        course.meeting_times.create!(
          begin_time: 900, end_time: 1050, day_of_week: :monday,
          meeting_schedule_type: :lecture, meeting_type: :class_meeting,
          start_date: course.start_date, end_date: course.end_date
        )
      end
    end

    it "lists terms chronologically with a meeting time count" do
      get "/reports/terms"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")

      csv = CSV.parse(response.body, headers: true)
      expect(csv.map { |r| r["term_uid"] }).to eq(%w[202620 202710])
      expect(csv.first.to_h).to include(
        "term" => "Spring 2026", "season" => "spring",
        "year" => "2026", "meeting_times" => "1"
      )
    end

    it "omits terms that have no schedule data" do
      get "/reports/terms"

      csv = CSV.parse(response.body, headers: true)
      expect(csv.map { |r| r["term_uid"] }).not_to include("202730")
    end

    it "sets public cache headers" do
      get "/reports/terms"

      expect(response.headers["Cache-Control"]).to include("public")
    end
  end
end
