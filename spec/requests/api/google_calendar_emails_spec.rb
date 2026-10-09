# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/api/user/google_calendar/emails", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }

  it "asks for an email on POST" do
    post "/api/user/google_calendar/emails", params: {}, headers: headers, as: :json

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body).to eq("error" => "email is required", "code" => "BAD_REQUEST")
  end

  it "answers NOT_FOUND on DELETE for an email that is not linked" do
    delete "/api/user/google_calendar/emails", params: { email: "nobody@example.com" }, headers: headers, as: :json

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body["code"]).to eq("NOT_FOUND")
  end
end
