# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/v1/catalog/schedule_options", type: :request do
  let(:term) { create(:term, uid: 202720) }

  def section(crn, code, schedule_type: "LEC", **attributes)
    subject_code, number = code.split
    CatalogCourse.find_or_create_by!(subject_code: subject_code, course_number: number.to_i)
    create(:course, term: term, crn: crn, subject: "Subject (#{subject_code})", course_number: number.to_i,
                    schedule_type: schedule_type, **attributes)
  end

  def meets(course, days, from, to)
    Array(days).each { |day| create(:course_meeting_time, course: course, day_of_week: day, begin_time: from, end_time: to) }
    course
  end

  def linked(lecture, lab)
    [ lecture, lab ].each { |course| course.update!(is_section_linked: true, links_fetched_at: Time.current) }
    create(:section_link, course: lecture, linked_course: lab, credit_hours: 0)
    create(:section_link, course: lab, linked_course: lecture, credit_hours: 4)
  end

  def post_options(body, path: "/api/v1/catalog/schedule_options", headers: {})
    post path, params: body, as: :json, headers: headers
  end

  let(:body) do
    {
      term_uid:    term.uid,
      courses:     [ { codes: [ "COMP 3350" ] }, { codes: [ "MATH 2300", "MATH 2860" ] } ],
      preferences: { day_off: "any", days: "fewer", breaks: "lunch", earliest: "09:00" },
      limit:       6
    }
  end

  before do
    lecture = meets(section(20410, "COMP 3350", credit_hours: 4), %i[monday wednesday], 1000, 1115)
    linked(lecture, meets(section(20411, "COMP 3350", schedule_type: "LAB", credit_hours: nil), :tuesday, 1300, 1450))
    meets(section(20520, "MATH 2300", credit_hours: 4), %i[monday wednesday], 1300, 1415)
    meets(section(20610, "MATH 2860", credit_hours: 4), %i[tuesday thursday], 900, 950)
  end

  it "builds and ranks schedules without a token" do
    post_options(body)

    expect(response).to have_http_status(:ok)
    data = response.parsed_body["data"]
    expect(data).to include("term" => { "uid" => 202720, "name" => term.name }, "count" => 2, "capped" => false,
                            "relax" => [], "not_offered" => [])
    best = data["schedules"].first
    expect(best).to include("rank" => 1, "crns" => %w[20410 20411 20520], "avoid_hits" => 0,
                            "courses" => [ { "code" => "COMP 3350", "crns" => %w[20410 20411] },
                                           { "code" => "MATH 2300", "crns" => %w[20520] } ])
    expect(best["highlights"]).to include("Thursdays and Fridays off", "Lunch break every day")
    expect(best["totals"]).to eq("credit_hours" => 8, "days" => %w[monday tuesday wednesday],
                                 "earliest_start" => "10:00", "latest_end" => "14:50", "meetings_before_nine" => 0)
    expect(response.headers["Cache-Control"]).not_to include("public")
  end

  it "counts the schedules on the count route" do
    post_options(body, path: "/api/v1/catalog/schedule_options/count")

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("data" => { "count" => 2, "capped" => false })
  end

  it "lists the preferences to drop when no schedule fits" do
    post_options(body.merge(preferences: { day_off: [ "monday" ], latest: "15:00" }))

    data = response.parsed_body["data"]
    expect(data).to include("count" => 0, "schedules" => [])
    expect(data["relax"]).to eq([ { "preference" => "day_off", "label" => "Allow classes on Monday", "count" => 2 } ])
  end

  it "answers 400 INVALID_FILTER for an unknown course, term, or preference" do
    [
      body.merge(courses: [ { codes: [ "ZZZZ 9999" ] } ]),
      body.merge(term_uid: 1),
      body.merge(preferences: { weekends: true }),
      body.merge(preferences: { breaks: "long" }),
      body.except(:courses)
    ].each do |bad|
      post_options(bad)

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["code"]).to eq("INVALID_FILTER")
    end
  end

  it "allows a POST from any origin" do
    process :options, "/api/v1/catalog/schedule_options/count",
            headers: { "Origin" => "https://example.com", "Access-Control-Request-Method" => "POST" }

    expect(response.headers["Access-Control-Allow-Origin"]).to eq("*")
    expect(response.headers["Access-Control-Allow-Methods"]).to include("POST")
  end

  # The term, the aliases, the catalog courses, the sections, and the fixed
  # levels of the preload: meetings, rooms, buildings, links, partners, and
  # the partners' links and meetings. Rails skips a level that it already
  # has, so the count can be lower, but it never grows with the courses.
  it "answers in a fixed number of queries, whatever the number of courses" do
    small = count_queries { post_options(body.merge(courses: [ { codes: [ "COMP 3350" ] } ])) }
    %w[PHIL ENGL HIST].each_with_index { |code, index| meets(section(20700 + index, "#{code} 2100"), :friday, 1000 + (index * 100), 1050 + (index * 100)) }
    large = count_queries do
      post_options(body.merge(courses: [ *body[:courses], { codes: [ "PHIL 2100" ] }, { codes: [ "ENGL 2100", "HIST 2100" ] } ]))
    end

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("data", "count")).to eq(2)
    expect([ small, large ]).to all(be <= 14)
  end
end
