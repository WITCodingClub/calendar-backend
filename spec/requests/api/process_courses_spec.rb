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
end
