# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Buildings", type: :request do
  let(:admin) do
    User.create!(email: "admin@wit.edu", password: "password123", confirmed_at: Time.current, access_level: :admin)
  end

  let!(:wentworth) { Building.create!(abbreviation: "WENTW", name: "Wentworth Test Hall") }

  before do
    Building.create!(abbreviation: "TBD", name: "To Be Determined")
    Building.create!(abbreviation: "ONLINE", name: "Online Section")
    allow(TwentyFiveLiveSyncJob).to receive(:in_progress?).and_return(false)
    sign_in admin
  end

  describe "GET /admin/buildings" do
    it "leaves out the TBD and ONLINE placeholders" do
      get admin_buildings_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("WENTW")
      expect(response.body).not_to include("To Be Determined")
      expect(response.body).not_to include("Online Section")
    end

    it "shows a building no sync has checked as never synced" do
      get admin_buildings_path

      expect(response.body).to include("Never synced")
      expect(response.body).to include("No 25Live sync has run yet.")
      expect(response.body).not_to include("Not in 25Live</span>")
    end

    it "shows a building a recent sync did not find as not in 25Live" do
      wentworth.update!(twenty_five_live_checked_at: 1.day.ago)

      get admin_buildings_path

      expect(response.body).to include("Not in 25Live</span>")
    end

    it "shows a building with an old check as out of date" do
      wentworth.update!(twenty_five_live_checked_at: 30.days.ago)

      get admin_buildings_path

      expect(response.body).to include("Sync out of date")
    end

    it "shows syncing while a sync job runs" do
      wentworth.update!(twenty_five_live_checked_at: 1.day.ago)
      allow(TwentyFiveLiveSyncJob).to receive(:in_progress?).and_return(true)

      get admin_buildings_path

      expect(response.body).to include("Syncing…")
      expect(response.body).to include("A 25Live sync is running.")
    end
  end

  describe "POST /admin/buildings/sync" do
    before { allow(TwentyFiveLiveSyncJob).to receive(:perform_later) }

    it "queues a sync" do
      post sync_admin_buildings_path

      expect(TwentyFiveLiveSyncJob).to have_received(:perform_later)
      expect(response).to redirect_to(admin_buildings_path)
    end

    it "does not queue a second sync while one runs" do
      allow(TwentyFiveLiveSyncJob).to receive(:in_progress?).and_return(true)

      post sync_admin_buildings_path

      expect(TwentyFiveLiveSyncJob).not_to have_received(:perform_later)
      expect(response).to redirect_to(admin_buildings_path)
    end
  end
end
