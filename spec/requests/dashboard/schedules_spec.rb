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
  end
end
