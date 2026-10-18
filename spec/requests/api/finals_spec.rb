# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Finals", type: :request do
  let(:user) { create(:user) }
  let(:term) { create(:term) }

  it "lists the finals of the user's courses in the term" do
    course = create(:course, term: term, course_number: 2000, title: "Algorithms")
    create(:enrollment, user: user, course: course)
    create(:final_exam, term: term, crn: course.crn, course: course, location: "WENTW 010")
    create(:final_exam, term: term)

    get "/api/user/finals", params: { term_uid: term.uid }, headers: auth_headers_for(user)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      "term_uid" => term.uid,
      "finals"   => [ {
        "course"     => "#{course.prefix}2000 Algorithms".squish,
        "crn"        => course.crn,
        "date"       => "2026-12-17",
        "start_time" => "08:00",
        "end_time"   => "10:00",
        "location"   => "WENTW 010"
      } ]
    )
  end

  it "answers 400 without a term and 404 for an unknown term" do
    get "/api/user/finals", headers: auth_headers_for(user)
    expect(response).to have_http_status(:bad_request)

    get "/api/user/finals", params: { term_uid: 1 }, headers: auth_headers_for(user)
    expect(response).to have_http_status(:not_found)
  end
end
