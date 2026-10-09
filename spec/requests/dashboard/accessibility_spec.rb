# frozen_string_literal: true

require "rails_helper"

# Issue #696: the dashboard nav and icon-only controls name themselves and
# mark the current page for assistive technology.
RSpec.describe "Dashboard accessibility", type: :request do
  let(:user) { create(:user, :with_processed_courses) }
  let(:page) { Nokogiri::HTML(response.body) }

  before { sign_in user }

  describe "layout" do
    before { get dashboard_schedule_path }

    it "starts with a skip link to the main content" do
      skip_link = page.at_css("body > a")

      expect(skip_link.text).to eq("Skip to content")
      expect(skip_link["href"]).to eq("#dashboard-main")
      expect(page.at_css("main#dashboard-main")).to be_present
    end

    it "labels both navs" do
      expect(page.css("nav").pluck("aria-label")).to eq([ "Main", "Main" ])
    end

    it "marks only the current page in each nav" do
      current = page.css("nav a[aria-current='page']")

      expect(current.pluck("href")).to eq([ dashboard_schedule_path, dashboard_schedule_path ])
    end

    it "names each rail item, which shows only an icon on medium screens" do
      rail_links = page.css("nav.lg\\:flex a")

      expect(rail_links).to all(satisfy { |link| link["aria-label"].present? })
    end

    it "hides every icon from assistive technology" do
      expect(page.css("svg")).to all(satisfy { |svg| svg["aria-hidden"] == "true" })
    end

    it "signs out with a DELETE form, not a link" do
      forms = page.css("form[action='#{destroy_user_session_path}']")

      expect(forms).not_to be_empty
      expect(forms.map { |form| form.at_css("input[name='_method']")["value"] }).to all(eq("delete"))
      expect(page.css("a[href='#{destroy_user_session_path}']")).to be_empty
    end
  end

  describe "schedule view toggle" do
    let(:term) { create(:term) }

    before do
      course = create(:course, term: term)
      create(:course_meeting_time, course: course)
      create(:enrollment, user: user, course: course)
    end

    it "marks the current view" do
      get dashboard_schedule_path, params: { term_uid: term.uid, view: "week" }

      current = page.css("[role='group'][aria-label='View'] a[aria-current='page']")
      expect(current.map { |link| link.text.strip }).to eq([ "Week" ])
    end

    it "names the week navigation links" do
      get dashboard_schedule_path, params: { term_uid: term.uid, view: "week" }

      expect(page.css("a[aria-label='Previous week']")).to be_present
      expect(page.css("a[aria-label='Next week']")).to be_present
    end

    it "names the month navigation links" do
      get dashboard_schedule_path, params: { term_uid: term.uid, view: "month" }

      expect(page.css("a[aria-label='Previous month']")).to be_present
      expect(page.css("a[aria-label='Next month']")).to be_present
    end
  end

  it "names the icon-only back link on the friend requests page" do
    get dashboard_friends_requests_path

    back = page.at_css("main a[href='#{dashboard_friends_path}']")
    expect(back["aria-label"]).to eq("Back to friends")
  end
end
