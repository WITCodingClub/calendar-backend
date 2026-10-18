# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/process_courses", type: :request do
  let(:user) { create(:user) }

  # The controller rescues the error and answers 500, so only the report shows
  # that it happened.
  it "reports an error that the controller rescues" do
    allow(Courses::Processor).to receive(:new).and_raise(RuntimeError, "synthetic failure")

    reports = capture_error_reports(RuntimeError) do
      post "/api/process_courses", params: { courses: [ { crn: 12345, term: 202710 } ] },
                                   headers: auth_headers_for(user), as: :json
    end

    expect(response).to have_http_status(:internal_server_error)
    expect(response.parsed_body).to eq("error" => "Failed to process courses", "code" => "INTERNAL_ERROR")
    expect(reports.size).to eq(1)
    expect(reports.first).to be_handled
    expect(reports.first.context).to include(user_id: user.id)
  end

  it "answers 503 with Retry-After at once while Banner cools down, and reports nothing" do
    allow(Courses::Processor).to receive(:new).and_raise(Catalog::BannerThrottle::CooldownError.new(42))

    reports = capture_error_reports do
      post "/api/process_courses", params: { courses: [ { crn: 12345, term: 202710 } ] },
                                   headers: auth_headers_for(user), as: :json
    end

    expect(response).to have_http_status(:service_unavailable)
    expect(response.headers["Retry-After"]).to eq("42")
    expect(response.parsed_body["code"]).to eq("BANNER_UNAVAILABLE")
    expect(reports).to be_empty
  end

  it "answers 503 on reprocess while Banner cools down" do
    allow(Courses::Reprocessor).to receive(:new).and_raise(Catalog::BannerThrottle::CooldownError.new(42))

    post "/api/courses/reprocess", params: { courses: [ { crn: 12345, term: 202710 } ] },
                                   headers: auth_headers_for(user), as: :json

    expect(response).to have_http_status(:service_unavailable)
  end
end
