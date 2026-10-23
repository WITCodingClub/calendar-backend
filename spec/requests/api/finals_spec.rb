# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Finals", type: :request do
  let(:user) { create(:user) }
  let(:term) { create(:term) }

  it "lists the finals of the user's courses in the term" do
    course = create(:course, term: term, course_number: 2000, title: "Algorithms")
    create(:enrollment, user: user, course: course)
    exam = create(:final_exam, term: term, crn: course.crn, course: course, location: "WENTW 010")
    create(:final_exam, term: term)

    get "/api/user/finals", params: { term_uid: term.uid }, headers: auth_headers_for(user)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      "term_uid"           => term.uid,
      "schedule_published" => true,
      "finals"             => [ {
        "id"            => exam.public_id,
        "course"        => "#{course.prefix}2000 Algorithms".squish,
        "crn"           => course.crn,
        "date"          => "2026-12-17",
        "start_time"    => "08:00",
        "end_time"      => "10:00",
        "location"      => "WENTW 010",
        "location_name" => "WENTW 010"
      } ]
    )
  end

  it "names the rooms of every final without a query for each final" do
    # A building for each final: the query cache hides repeats of one building.
    add_final = lambda do |abbreviation, date|
      building = create(:building, abbreviation: abbreviation, name: "#{abbreviation} Hall")
      create(:room, building: building, number: "112")
      course = create(:course, term: term)
      create(:enrollment, user: user, course: course)
      create(:final_exam, term: term, crn: course.crn, course: course, location: "#{abbreviation} 112", exam_date: date)
    end
    request_finals = -> { get "/api/user/finals", params: { term_uid: term.uid }, headers: auth_headers_for(user) }

    add_final.call("ZZQ", Date.new(2026, 12, 15))
    request_finals.call
    one = count_queries { request_finals.call }

    add_final.call("ZZR", Date.new(2026, 12, 16))
    add_final.call("ZZS", Date.new(2026, 12, 17))
    three = count_queries { request_finals.call }

    expect(three).to eq(one)
    expect(response.parsed_body["finals"].pluck("location_name")).to eq([ "ZZQ Hall 112", "ZZR Hall 112", "ZZS Hall 112" ])
  end

  it "says when the term has no finals schedule yet" do
    create(:enrollment, user: user, course: create(:course, term: term))

    get "/api/user/finals", params: { term_uid: term.uid }, headers: auth_headers_for(user)

    expect(response.parsed_body).to include("schedule_published" => false, "finals" => [])
  end

  it "answers 400 without a term and 404 for an unknown term" do
    get "/api/user/finals", headers: auth_headers_for(user)
    expect(response).to have_http_status(:bad_request)

    get "/api/user/finals", params: { term_uid: 1 }, headers: auth_headers_for(user)
    expect(response).to have_http_status(:not_found)
  end
end
