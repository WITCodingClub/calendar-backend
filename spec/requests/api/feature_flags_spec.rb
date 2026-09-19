# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Users feature flags", type: :request do
  let(:user) { create(:user) }

  it "lists only the flags in FlipperFlags" do
    get "/api/user/feature_flags", headers: auth_headers_for(user)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["feature_flags"].keys).to match_array(FlipperFlags::ALL_FLAGS.map(&:to_s))
  end

  it "reports the removed v1 flag as unknown" do
    get "/api/user/flag_enabled", params: { flag_name: "v1" }, headers: auth_headers_for(user)

    expect(response).to have_http_status(:not_found)
  end
end
