# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::NavHelper, type: :helper do
  describe "#dashboard_nav_active?" do
    def active?(request_path, path)
      allow(helper.request).to receive(:path).and_return(request_path)
      helper.dashboard_nav_active?(path)
    end

    it "matches the page itself" do
      expect(active?("/dashboard/friends", "/dashboard/friends")).to be(true)
    end

    it "matches a page under the item" do
      expect(active?("/dashboard/friends/requests", "/dashboard/friends")).to be(true)
    end

    it "does not match a page that only shares a prefix" do
      expect(active?("/dashboard/friendsx", "/dashboard/friends")).to be(false)
    end

    it "matches the dashboard root only on the root" do
      expect(active?("/dashboard", "/dashboard")).to be(true)
      expect(active?("/dashboard/schedule", "/dashboard")).to be(false)
    end
  end

  describe "#dashboard_more_items" do
    it "lists the pages for the More sheet" do
      expect(helper.dashboard_more_items.pluck(:label)).to eq([ "Accounts", "ICS Feed", "Notifications", "Settings" ])
    end
  end
end
