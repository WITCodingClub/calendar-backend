# frozen_string_literal: true

require "rails_helper"

# The System Tools links go to mounted engines with their own layouts, so the
# admin nav opens them in a new tab.
RSpec.describe "Admin navigation links", type: :request do
  let(:owner) { create(:user, access_level: :owner) }
  let(:page) { Nokogiri::HTML(response.body) }
  let(:engine_paths) { [ "/admin/jobs", "/admin/flipper", "/admin/blazer", "/admin/pghero", "/admin/audits" ] }

  before do
    stub_request(:get, "https://api.github.com/repos/WITCodingClub/calendar/releases/latest")
      .to_return(status: 200, body: { tag_name: "v0.0.0" }.to_json)
    allow(TwentyFiveLiveSyncJob).to receive(:in_progress?).and_return(false)
    sign_in owner
  end

  it "opens engine links in a new tab in the sidebars and the palette" do
    get admin_buildings_path

    engine_paths.each do |path|
      links = page.css("a[href='#{path}']")

      expect(links.size).to eq(3), "expected 3 links to #{path}, got #{links.size}"
      expect(links).to all(satisfy { |a| a["target"] == "_blank" && a["rel"] == "noopener" })
    end
  end

  it "opens in-app links in the same tab" do
    get admin_buildings_path

    links = page.css("a[href='#{admin_service_account_index_path}'], a[href='#{admin_users_path}']")

    expect(links).not_to be_empty
    expect(links.map { |a| a["target"] }).to all(be_nil)
  end

  it "marks engine links as external in the navigation JSON" do
    get admin_navigation_path

    items = response.parsed_body["categories"].flat_map { |c| c["items"] }
    external = items.select { |i| i["external"] }.map { |i| i["path"] }

    expect(external).to match_array(engine_paths)
  end
end
