# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin service account", type: :request do
  before do
    stub_request(:get, "https://api.github.com/repos/WITCodingClub/calendar/releases/latest")
      .to_return(status: 200, body: { tag_name: "v0.0.0" }.to_json)
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:google, :client_id).and_return("client-id")
    allow(Rails.application.credentials).to receive(:dig).with(:google, :client_secret).and_return("client-secret")
  end

  it "sends an owner to Google to authorize" do
    sign_in create(:user, access_level: :owner)

    get admin_service_account_authorize_path

    expect(response).to have_http_status(:redirect)
    expect(response.location).to start_with("https://accounts.google.com/o/oauth2/auth")
  end

  it "sends a super admin back to the admin root" do
    sign_in create(:user, access_level: :super_admin)

    get admin_service_account_authorize_path

    expect(response).to redirect_to(admin_root_path)
  end
end
