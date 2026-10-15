# frozen_string_literal: true

require "rails_helper"

# Issue #691: both navs reach every dashboard page, with the same labels.
RSpec.describe "Dashboard nav", type: :request do
  let(:user) { create(:user, :with_processed_courses) }
  let(:page) { Nokogiri::HTML(response.body) }
  let(:rail) { page.at_css("nav.lg\\:flex") }
  let(:mobile) { page.at_css("nav.lg\\:hidden") }

  let(:pages) do
    {
      dashboard_root_path                 => "Overview",
      dashboard_schedule_path             => "Schedule",
      dashboard_calendar_preferences_path => "Preferences",
      dashboard_connected_accounts_path   => "Accounts",
      dashboard_ics_feed_path             => "ICS Feed",
      dashboard_notifications_path        => "Notifications",
      dashboard_friends_path              => "Friends",
      dashboard_settings_path             => "Settings"
    }
  end

  def labels(nav)
    nav.css("a").to_h { |link| [ link["href"], link.text.strip ] }
  end

  before do
    sign_in user
    get dashboard_schedule_path
  end

  it "links every page from the desktop rail" do
    expect(labels(rail)).to include(pages)
  end

  it "links every page from the mobile nav with the same labels" do
    expect(labels(mobile)).to include(pages)
  end

  it "puts the pages that do not fit the mobile bar in the More sheet" do
    sheet = mobile.at_css("#dashboard-more[popover]")

    expect(mobile.at_css("button[popovertarget='dashboard-more']").text.strip).to eq("More")
    expect(labels(sheet).values).to eq([ "Accounts", "ICS Feed", "Notifications", "Settings" ])
  end

  it "signs out from the More sheet with a 44px target" do
    form = mobile.at_css("#dashboard-more form[action='#{destroy_user_session_path}']")

    expect(form.at_css("button")["class"]).to include("min-h-11")
  end

  it "has no sign out in the mobile top bar" do
    expect(page.css("header form[action='#{destroy_user_session_path}']")).to be_empty
  end

  it "marks More as active on a page in the sheet" do
    get dashboard_settings_path

    expect(mobile.at_css("button[popovertarget='dashboard-more']")["class"]).to include("text-on-secondary-container")
    expect(mobile.css("a[aria-current='page']").pluck("href")).to eq([ dashboard_settings_path ])
  end

  it "does not mark More as active on a page in the bar" do
    expect(mobile.at_css("button[popovertarget='dashboard-more']")["class"]).to include("text-on-surface-variant")
  end
end
