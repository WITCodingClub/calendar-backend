# frozen_string_literal: true

require "rails_helper"

# Issue #655: the admin sidebar lists every admin section, marks the current
# one, and shows the same links in the small-screen drawer.
RSpec.describe "Admin sidebar navigation", type: :request do
  let(:page) { Nokogiri::HTML(response.body) }
  let(:desktop_nav) { page.css("aside.lg\\:flex nav[aria-label='Admin sections']") }
  let(:drawer_nav) { page.css("[data-admin-sidebar-target='overlay'] nav[aria-label='Admin sections']") }

  let(:section_paths) do
    [
      admin_users_path, admin_courses_path, admin_course_catalog_path, admin_terms_path,
      admin_buildings_path, admin_rooms_path, admin_faculties_path, admin_rmp_ratings_path,
      admin_finals_schedules_path, admin_calendars_path, admin_calendar_events_path,
      admin_university_calendar_events_path, admin_service_account_index_path
    ]
  end

  before do
    stub_request(:get, "https://api.github.com/repos/WITCodingClub/calendar/releases/latest")
      .to_return(status: 200, body: { tag_name: "v0.0.0" }.to_json)
    allow(TwentyFiveLiveSyncJob).to receive(:in_progress?).and_return(false)
  end

  context "when an owner is signed in" do
    before { sign_in create(:user, access_level: :owner) }

    it "links to all 13 sections in the sidebar and in the drawer" do
      get admin_root_path

      [ desktop_nav, drawer_nav ].each do |nav|
        hrefs = nav.css("a").pluck("href")
        expect(hrefs).to include(*section_paths)
      end
    end

    it "marks only the current section" do
      get admin_rooms_path

      current = desktop_nav.css("a[aria-current='page']")
      expect(current.pluck("href")).to eq([ admin_rooms_path ])
    end

    it "marks the dashboard only on the dashboard" do
      get admin_root_path

      expect(desktop_nav.css("a[aria-current='page']").pluck("href")).to eq([ admin_root_path ])
    end

    it "does not mark Courses on the course catalog page" do
      stub_request(:get, %r{\Ahttps://selfservice\.wit\.edu/StudentRegistrationSsb/ssb/courseSearch/getTerms})
        .to_return(status: 200, body: "[]", headers: { "Content-Type" => "application/json" })

      get admin_course_catalog_path

      expect(desktop_nav.css("a[aria-current='page']").pluck("href")).to eq([ admin_course_catalog_path ])
    end
  end

  context "when an admin is signed in" do
    before { sign_in create(:user, :admin) }

    it "hides the sections for higher access levels" do
      get admin_root_path

      hrefs = desktop_nav.css("a").pluck("href")
      expect(hrefs).to include(admin_users_path, admin_buildings_path)
      expect(hrefs).not_to include(admin_course_catalog_path, admin_service_account_index_path, "/admin/flipper")
    end
  end
end
