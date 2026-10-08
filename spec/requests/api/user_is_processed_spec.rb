# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/user/is_processed", type: :request do
  let(:user) { create(:user) }
  let(:term) { create(:term) }

  def post_is_processed(term_uid = term.uid)
    post "/api/user/is_processed", params: { term_uid: term_uid }, headers: auth_headers_for(user), as: :json
  end

  it "reports a term with no enrollments and no status as not started" do
    post_is_processed

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("processed" => false, "status" => "not_started", "error_code" => nil)
  end

  it "reports a term with enrollments and no status as processed" do
    create(:enrollment, user: user, course: create(:course, term: term))

    post_is_processed

    expect(response.parsed_body).to eq("processed" => true, "status" => "processed", "error_code" => nil)
  end

  it "does not report a term as processed while a job still processes it" do
    create(:enrollment, user: user, course: create(:course, term: term))
    create(:term_processing_status, user: user, term: term, status: "processing")

    post_is_processed

    expect(response.parsed_body).to eq("processed" => false, "status" => "processing", "error_code" => nil)
  end

  it "reports a pending term" do
    create(:term_processing_status, user: user, term: term, status: "pending")

    post_is_processed

    expect(response.parsed_body).to eq("processed" => false, "status" => "pending", "error_code" => nil)
  end

  it "reports a failed term with its error code" do
    create(:term_processing_status, :failed, user: user, term: term)

    post_is_processed

    expect(response.parsed_body).to eq("processed" => false, "status" => "failed", "error_code" => "banner_unavailable")
  end

  it "reports a processed term" do
    create(:term_processing_status, user: user, term: term, status: "processed")

    post_is_processed

    expect(response.parsed_body).to eq("processed" => true, "status" => "processed", "error_code" => nil)
  end

  it "reads only the status of the current user" do
    create(:term_processing_status, :failed, user: create(:user), term: term)

    post_is_processed

    expect(response.parsed_body["status"]).to eq("not_started")
  end

  it "requires a term_uid" do
    post "/api/user/is_processed", params: {}, headers: auth_headers_for(user), as: :json

    expect(response).to have_http_status(:bad_request)
  end

  it "returns not found for an unknown term" do
    post_is_processed(199910)

    expect(response).to have_http_status(:not_found)
  end
end
