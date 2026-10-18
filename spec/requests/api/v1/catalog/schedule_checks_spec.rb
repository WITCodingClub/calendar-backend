# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /api/v1/catalog/schedule_check", type: :request do
  let(:term) { create(:term) }

  it "checks the CRNs without a token" do
    lecture = create(:course, term: term, crn: 20397)
    create(:course_meeting_time, course: lecture, day_of_week: :monday, begin_time: 1000, end_time: 1115)

    get "/api/v1/catalog/schedule_check", params: { term_uid: term.uid, crn: "20397,99999" }

    expect(response).to have_http_status(:ok)
    data = response.parsed_body["data"]
    expect(data["sections"].pluck("crn")).to eq([ 20397 ])
    expect(data["not_found"]).to eq([ 99999 ])
    expect(data["totals"]["days"]).to eq([ "monday" ])
  end

  it "answers 400 without CRNs" do
    get "/api/v1/catalog/schedule_check", params: { term_uid: term.uid }

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body["code"]).to eq("INVALID_FILTER")
  end

  it "answers 400 for an unknown term" do
    get "/api/v1/catalog/schedule_check", params: { term_uid: 1, crn: "20397" }

    expect(response).to have_http_status(:bad_request)
  end
end
