# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PUT /api/user/course_outcomes", type: :request do
  let(:user) { create(:user) }
  let(:term) { create(:term, uid: 202610, year: 2025, season: :fall) }

  it "stores the outcomes and returns a result for each term" do
    course = create(:course, term: term)
    create(:enrollment, user: user, course: course)

    put "/api/user/course_outcomes",
        params:  { terms: [ { term: "Fall 2025", courses: [ { crn: course.crn.to_s, outcome: "passed_below_c" },
                                                              { crn: "99999", outcome: "failed" } ] } ] },
        headers: auth_headers_for(user), as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("terms" => [ { "term" => "202610", "updated" => 1, "unknown_crns" => [ "99999" ] } ])
    expect(user.course_outcomes.sole).to have_attributes(term_uid: 202610, crn: course.crn, outcome: "passed_below_c")
  end

  it "answers 422 with invalid_outcome for a letter grade" do
    put "/api/user/course_outcomes",
        params:  { terms: [ { term: "202610", courses: [ { crn: "1", outcome: "A-" } ] } ] },
        headers: auth_headers_for(user), as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to include("code" => "invalid_outcome")
  end

  it "answers 422 when terms is missing" do
    put "/api/user/course_outcomes", params: {}, headers: auth_headers_for(user), as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to eq("terms must be a non-empty list")
  end
end
