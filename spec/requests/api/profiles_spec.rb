# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /api/user", type: :request do
  let(:user) { create(:user) }

  it "returns the public id, the email, and the ICS feed URL in one response" do
    get "/api/user", headers: auth_headers_for(user)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      "pub_id"  => user.public_id,
      "email"   => user.email,
      "ics_url" => user.cal_url_with_extension
    )
  end
end
