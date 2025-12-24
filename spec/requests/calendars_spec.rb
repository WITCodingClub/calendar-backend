# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Calendars", type: :request do
  describe "GET /calendar/:calendar_token.ics" do
    let(:user) do
      u = User.create!(calendar_token: "test-token-123")
      u.emails.create!(email: "test@example.com", primary: true)
      u
    end

    context "when requesting ICS format" do
      before do
        get "/calendar/#{user.calendar_token}.ics"
      end

      it "returns success" do
        expect(response).to have_http_status(:success)
      end

      it "returns text/calendar content type" do
        expect(response.content_type).to match(/text\/calendar/)
      end

      it "sets Cache-Control header with 1 hour max-age" do
        expect(response.headers["Cache-Control"]).to eq("max-age=3600, private, must-revalidate")
      end

      it "sets X-Published-TTL header for iCalendar refresh hint" do
        expect(response.headers["X-Published-TTL"]).to eq("PT1H")
      end

      it "sets Refresh-Interval header" do
        expect(response.headers["Refresh-Interval"]).to eq("3600")
      end
    end

    context "when calendar_token is invalid" do
      it "returns 404 not found" do
        get "/calendar/invalid-token.ics"
        expect(response).to have_http_status(:not_found)
      end
    end

    context "with final exams" do
      let(:term) { create(:term, year: 2024, season: :fall) }
      let(:course) { create(:course, term: term, title: "Introduction to Computer Science") }
      let!(:enrollment) { create(:enrollment, user: user, course: course, term: term) }
      let!(:final_exam) do
        create(:final_exam,
               course: course,
               term: term,
               exam_date: 1.week.from_now.to_date,
               start_time: 900,
               end_time: 1100)
      end

      it "includes final exam events in the calendar" do
        get "/calendar/#{user.calendar_token}.ics"

        expect(response).to have_http_status(:success)
        ics_content = response.body

        expect(ics_content).to include("Final Exam:")
        expect(ics_content).to include("final-exam-#{final_exam.id}@calendar-util.wit.edu")
      end
    end

    context "with university calendar events" do
      let!(:holiday) do
        create(:university_calendar_event,
               category: "holiday",
               summary: "Thanksgiving Break",
               start_time: 1.week.from_now.beginning_of_day,
               end_time: 1.week.from_now.end_of_day,
               all_day: true)
      end

      let!(:campus_event) do
        create(:university_calendar_event,
               category: "campus_event",
               summary: "Spring Concert",
               start_time: 2.weeks.from_now.beginning_of_day,
               end_time: 2.weeks.from_now.end_of_day,
               all_day: true)
      end

      it "always includes holidays in the calendar" do
        get "/calendar/#{user.calendar_token}.ics"

        expect(response).to have_http_status(:success)
        ics_content = response.body

        expect(ics_content).to include("Thanksgiving Break")
        expect(ics_content).to include("university-#{holiday.ics_uid}@calendar-util.wit.edu")
      end

      it "excludes non-holiday events when user has not opted in" do
        get "/calendar/#{user.calendar_token}.ics"

        expect(response).to have_http_status(:success)
        ics_content = response.body

        expect(ics_content).not_to include("Spring Concert")
      end

      context "when user has opted in to university events" do
        before do
          # Clear any existing config and create a new one with university events enabled
          UserExtensionConfig.where(user: user).destroy_all
          UserExtensionConfig.create!(
            user: user,
            sync_university_events: true,
            university_event_categories: ["campus_event"]
          )
        end

        it "includes opted-in category events" do
          get "/calendar/#{user.calendar_token}.ics"

          expect(response).to have_http_status(:success)
          ics_content = response.body

          expect(ics_content).to include("Spring Concert")
          expect(ics_content).to include("university-#{campus_event.ics_uid}@calendar-util.wit.edu")
        end
      end
    end

    context "with holiday exclusions on meeting times" do
      let(:term) { create(:term, year: 2024, season: :fall) }
      let(:course) { create(:course, term: term) }
      let!(:enrollment) { create(:enrollment, user: user, course: course, term: term) }
      let!(:meeting_time) do
        create(:meeting_time,
               course: course,
               day_of_week: :monday,
               begin_time: 900,
               end_time: 950,
               start_date: Date.new(2024, 8, 26),
               end_date: Date.new(2024, 12, 13))
      end

      let!(:labor_day) do
        create(:university_calendar_event,
               category: "holiday",
               summary: "Labor Day",
               start_time: Time.zone.local(2024, 9, 2, 0, 0, 0),
               end_time: Time.zone.local(2024, 9, 2, 23, 59, 59),
               all_day: true)
      end

      it "includes EXDATE for holidays on meeting days" do
        get "/calendar/#{user.calendar_token}.ics"

        expect(response).to have_http_status(:success)
        ics_content = response.body

        # Should have an EXDATE for Labor Day (Sept 2, 2024 - a Monday)
        expect(ics_content).to include("EXDATE")
        expect(ics_content).to include("20240902")
      end
    end
  end
end
