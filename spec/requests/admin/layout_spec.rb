# frozen_string_literal: true

require "rails_helper"

# Stimulus only runs an action when the element sits inside the controller's
# element. Issue #572: the sidebar controller was on the desktop sidebar, so
# the small-screen menu button did nothing.
RSpec.describe "Admin layout", type: :request do
  let(:admin) do
    User.create!(email: "admin@wit.edu", password: "password123", confirmed_at: Time.current, access_level: :admin)
  end

  let(:page) { Nokogiri::HTML(response.body) }

  before do
    allow(TwentyFiveLiveSyncJob).to receive(:in_progress?).and_return(false)
    sign_in admin
    get admin_buildings_path
  end

  it "puts the menu button and the overlay inside the admin-sidebar controller" do
    open_button = page.at_css("[data-action~='click->admin-sidebar#open']")
    overlay = page.at_css("[data-admin-sidebar-target='overlay']")

    expect(open_button).to be_present
    expect(overlay).to be_present
    expect(open_button.ancestors("[data-controller~='admin-sidebar']")).to be_present
    expect(overlay.ancestors("[data-controller~='admin-sidebar']")).to be_present
  end

  # Issue #513: the header search button sat outside the command-palette
  # controller, so a click did nothing.
  it "puts the search button and the palette inside the command-palette controller" do
    open_button = page.at_css("[data-action~='click->command-palette#open']")
    panel = page.at_css("[data-command-palette-target='panel']")

    expect(open_button).to be_present
    expect(panel).to be_present
    expect(open_button.ancestors("[data-controller~='command-palette']")).to be_present
    expect(panel.ancestors("[data-controller~='command-palette']")).to be_present
  end

  # Issue #513: Cloudflare Email Obfuscation showed "[email protected]".
  it "turns off Cloudflare email obfuscation for the page" do
    expect(response.body).to match(%r{<!--email_off-->.*admin@wit\.edu.*<!--/email_off-->}m)
  end

  it "closes the overlay from the backdrop and the close button" do
    overlay = page.at_css("[data-admin-sidebar-target='overlay']")

    expect(overlay.css("[data-action~='click->admin-sidebar#close']").size).to eq(2)
  end

  it "only names Stimulus controllers that exist" do
    known = Rails.root.glob("app/javascript/controllers/**/*_controller.js").map do |path|
      path.relative_path_from(Rails.root.join("app/javascript/controllers")).to_s
        .delete_suffix("_controller.js").tr("_", "-").gsub("/", "--")
    end

    used = page.css("[data-controller]").flat_map { |node| node["data-controller"].split }

    expect(used - known).to be_empty
  end
end
