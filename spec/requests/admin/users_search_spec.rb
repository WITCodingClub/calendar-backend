# frozen_string_literal: true

require "rails_helper"

# Issue #513: the users search form loads results into a Turbo frame. The frame
# response uses the turbo_rails/frame layout, where the Cloudflare decoder never
# runs, so emails showed as "[email protected]".
RSpec.describe "Admin users search", type: :request do
  let(:admin) { create(:user, :admin) }

  before do
    stub_request(:get, "https://api.github.com/repos/WITCodingClub/calendar/releases/latest")
      .to_return(status: 200, body: { tag_name: "v0.0.0" }.to_json)
    allow(TwentyFiveLiveSyncJob).to receive(:in_progress?).and_return(false)
    create(:user, email: "student@wit.edu")
    sign_in admin
  end

  it "returns the matching email inside email_off markers for a frame request" do
    get admin_users_path, params: { search: "student" }, headers: { "Turbo-Frame" => "users_table" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to match(%r{<!--email_off-->.*student@wit\.edu.*<!--/email_off-->}m)
  end
end
