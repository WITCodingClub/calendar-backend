# frozen_string_literal: true

require "rails_helper"

# Users with no connected calendar showed "Needs sync", but the nightly sync
# skips them, so the badge never cleared.
RSpec.describe "Admin users Needs sync badge", type: :request do
  let(:admin) { create(:user, :admin) }

  before do
    stub_request(:get, "https://api.github.com/repos/WITCodingClub/calendar/releases/latest")
      .to_return(status: 200, body: { tag_name: "v0.0.0" }.to_json)
    allow(TwentyFiveLive::SyncJob).to receive(:in_progress?).and_return(false)
    sign_in admin
  end

  it "hides the badge for a flagged user with no calendar" do
    user = create(:user, calendar_needs_sync: true)

    get admin_users_path
    expect(response.body).not_to include("Needs sync")

    get admin_user_path(user)
    expect(response.body).not_to include("Needs sync")
  end

  it "shows the badge for a flagged user with a calendar" do
    user = create(:course_calendar).oauth_credential.user
    user.update!(calendar_needs_sync: true)

    get admin_users_path
    expect(response.body).to include("Needs sync")

    get admin_user_path(user)
    expect(response.body).to include("Needs sync")
  end
end
