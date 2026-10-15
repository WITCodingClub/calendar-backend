# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /api/user/course_history", type: :request do
  let(:user) { create(:user) }

  # Two terms with two courses each: Prosopite fails the request if the
  # history loads the courses one term at a time.
  it "lists each processed term with its courses in one load" do
    terms = [ create(:term, year: 2025, season: :fall), create(:term, year: 2026, season: :spring) ]
    terms.each do |term|
      2.times do
        course = create(:course, term: term)
        create(:course_meeting_time, course: course)
        create(:enrollment, user: user, course: course)
      end
    end

    get "/api/user/course_history", headers: auth_headers_for(user)

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["terms"].pluck("uid")).to eq(terms.reverse.map(&:uid))
    expect(body["terms"].map { |term| term["courses"].length }).to eq([ 2, 2 ])
  end
end
