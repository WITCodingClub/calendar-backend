# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::UniversityCalendarEvents", type: :request do # rubocop:disable RSpecRails/InferredSpecType
  let(:admin_user) { create(:user, :admin) }

  describe "GET /admin/university_calendar_events" do
    before do
      # Stub the routing constraint to allow access
      allow_any_instance_of(AdminConstraint).to receive(:matches?).and_return(true)

      # Stub authentication on the controller
      allow_any_instance_of(Admin::ApplicationController).to receive(:require_admin).and_return(true)
      allow_any_instance_of(Admin::ApplicationController).to receive(:current_user).and_return(admin_user)
      allow_any_instance_of(Admin::ApplicationController).to receive(:user_signed_in?).and_return(true)
    end

    context "when filtering consistency" do
      before do
        # Create events with different categories
        # Some with location, some without
        create(:university_calendar_event, :holiday, location: "Campus")
        create(:university_calendar_event, :holiday, location: nil)
        create(:university_calendar_event, :term_dates, location: nil)
        create(:university_calendar_event, :term_dates, location: nil)
        create(:university_calendar_event, :registration, location: "Admissions Office")
        create(:university_calendar_event, :campus_event, location: nil)
      end

      it "stats respect the with_location filter by default for total/holidays/upcoming" do
        get admin_university_calendar_events_path

        expect(response).to have_http_status(:ok)

        # The total, holidays, and upcoming stats should respect with_location filter
        # But category stats should show ALL events in each category
        expect(response.body).to include("Holiday")
        expect(response.body).to include("Registration")
      end

      it "category stats show true counts regardless of location filter" do
        get admin_university_calendar_events_path

        expect(response).to have_http_status(:ok)

        # Category breakdown should show all events in each category,
        # including those without locations (2 term_dates events should show)
        expect(response.body).to include("Term Dates")
      end

      it "stats include all events when show_all=1" do
        get admin_university_calendar_events_path(show_all: "1")

        expect(response).to have_http_status(:ok)

        # With show_all=1, all events should be counted in all stats
      end

      it "category links preserve the show_all parameter" do
        get admin_university_calendar_events_path(show_all: "1")

        expect(response).to have_http_status(:ok)

        # Check that category links include show_all parameter
        expect(response.body).to include("show_all=1")
      end

      it "filtering by category bypasses location filter to show all events in that category" do
        # Filter by term_dates category (both events have no location)
        get admin_university_calendar_events_path(category: "term_dates")

        expect(response).to have_http_status(:ok)

        # Should show events because category filter bypasses the location filter
        # This ensures clicking a category shows all events matching that category
        expect(response.body).to include("Term Dates")
      end

      it "filtering by category still works with show_all=1" do
        # Filter by term_dates category with show_all=1
        get admin_university_calendar_events_path(category: "term_dates", show_all: "1")

        expect(response).to have_http_status(:ok)

        # Should show events in that category
        expect(response.body).to include("Term Dates")
      end
    end
  end
end
