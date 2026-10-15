# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Schedules", type: :request do
  let(:user)   { create(:user) }
  let(:term)   { create(:term) }
  let(:course) { create(:course, term: term, subject: "COMP", course_number: 1050, title: "Computer Science I") }

  before do
    create(:course_meeting_time, course: course)
    create(:enrollment, user: user, course: course)
    sign_in user
  end

  describe "GET /dashboard/schedule" do
    it "lists the signed-in user's courses" do
      get dashboard_schedule_path, params: { term_uid: term.uid, view: "list" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("My Schedule")
      expect(response.body).to include("COMP 1050")
      expect(response.body).to include("Computer Science I")
    end

    it "links the week navigation to the user's own schedule" do
      get dashboard_schedule_path, params: { term_uid: term.uid, view: "week", week_start: "2026-09-14" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(
        ERB::Util.html_escape(dashboard_schedule_path(view: "week", term_uid: term.uid, week_start: "2026-09-07"))
      )
      expect(response.body).to include("COMP 1050")
    end

    it "renders the month view" do
      get dashboard_schedule_path, params: { term_uid: term.uid, view: "month", month: "2026-09" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("September 2026")
      expect(response.body).to include("COMP 1050")
    end

    # Issue #697: the schedule is readable on a phone and with a screen reader.
    describe "layout and accessibility" do
      let(:page) { Nokogiri::HTML(response.body) }

      it "shows the list on small screens and the week grid on larger ones when no view is given" do
        get dashboard_schedule_path, params: { term_uid: term.uid }

        expect(page.at_css("div.sm\\:hidden .m3-card").text).to include("Computer Science I")
        expect(page.at_css("div.hidden.sm\\:block ul[aria-label]")).to be_present
        current = page.css("[role='group'][aria-label='View'] a[aria-current='page']").map { |link| link.text.strip }
        expect(current).to eq([ "List", "Week" ])
        expect(page.at_css("input[name='view']")).to be_nil
      end

      it "hides Saturday and Sunday when no course meets on them" do
        get dashboard_schedule_path, params: { term_uid: term.uid, view: "week", week_start: "2026-09-14" }

        expect(page.css("ul[aria-label]").pluck("aria-label")).to eq([
          "Monday, September 14", "Tuesday, September 15", "Wednesday, September 16",
          "Thursday, September 17", "Friday, September 18"
        ])
      end

      it "shows Saturday when a course meets on it" do
        create(:course_meeting_time, course: course, day_of_week: :saturday)

        get dashboard_schedule_path, params: { term_uid: term.uid, view: "week", week_start: "2026-09-14" }

        saturday = page.at_css("ul[aria-label='Saturday, September 19']")
        expect(saturday.at_css("li[title]")["title"]).to start_with("COMP 1050, Computer Science I")
        expect(page.at_css("ul[aria-label='Sunday, September 20']")).to be_nil
        expect(response.body).to include("Sep 14 – Sep 19, 2026")
      end

      it "names each course block and uses theme text for it" do
        get dashboard_schedule_path, params: { term_uid: term.uid, view: "week", week_start: "2026-09-14" }

        block = page.at_css("ul[aria-label='Monday, September 14'] li[title]")
        expect(block["title"]).to start_with("COMP 1050, Computer Science I")
        expect(block.at_css(".sr-only").text).to eq(block["title"])
        expect(block["class"]).to include("text-on-surface")
      end

      %w[week month].each do |view|
        it "uses no text under 12 px and no faded text in the #{view} view" do
          get dashboard_schedule_path, params: { term_uid: term.uid, view: view, week_start: "2026-09-14", month: "2026-09" }

          main = page.at_css("main").inner_html
          expect(main).not_to match(/text-\[(9|10|11)px\]|font-size: ?(9|10|11)px/)
          expect(main).not_to match(%r{text-on-surface-variant/\d+|opacity-\d+|rgba\(0,0,0})
        end
      end

      it "labels each month day as a list of its courses" do
        get dashboard_schedule_path, params: { term_uid: term.uid, view: "month", month: "2026-09" }

        monday = page.at_css("ul[aria-label='Monday, September 14']")
        expect(monday.at_css("li[title]")["title"]).to start_with("COMP 1050, Computer Science I")
      end
    end
  end
end
