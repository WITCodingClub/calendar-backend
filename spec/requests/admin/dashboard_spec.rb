# frozen_string_literal: true

require "rails_helper"

# Issue #655: the admin home page shows key counts, recent sign-ups, sync
# health, failed jobs, and links to the tools the user can open.
RSpec.describe "Admin dashboard", type: :request do
  let(:page) { Nokogiri::HTML(response.body) }

  before do
    stub_request(:get, "https://api.github.com/repos/WITCodingClub/calendar/releases/latest")
      .to_return(status: 200, body: { tag_name: "v0.0.0" }.to_json)
  end

  context "when a super admin is signed in" do
    before { sign_in create(:user, :super_admin) }

    it "lists recent sign-ups" do
      create(:user, first_name: "Nina", last_name: "Newcomer")

      get admin_root_path

      expect(page.at_css("#recent-sign-ups").text).to include("Nina Newcomer")
    end

    it "shows a failed job with its error and a link to the job dashboard" do
      job = SolidQueue::Job.create!(queue_name: "default", class_name: "GoogleCalendarSyncJob", arguments: {}, active_job_id: SecureRandom.uuid)
      SolidQueue::FailedExecution.create!(job: job, error: { exception_class: "Signet::AuthorizationError", message: "invalid_grant", backtrace: [] })

      get admin_root_path

      failed = page.at_css("#failed-jobs")
      expect(failed.text).to include("GoogleCalendarSyncJob", "Signet::AuthorizationError: invalid_grant")
      expect(failed.css("a").pluck("href")).to include(a_string_including(job.active_job_id))
    end

    it "shows stale calendars in sync health" do
      create(:course_calendar, last_synced_at: 2.days.ago)

      get admin_root_path

      expect(page.at_css("#sync-health").text).to include("Some stale").or include("Many stale")
    end

    it "links to PgHero, Flipper, and the job dashboard in new tabs" do
      get admin_root_path

      links = page.css("#tools a")
      expect(links.pluck("href")).to include("/admin/pghero", "/admin/flipper", "/admin/jobs")
      expect(links.pluck("target").uniq).to eq([ "_blank" ])
    end
  end

  context "when an admin is signed in" do
    before { sign_in create(:user, :admin) }

    # Job errors can hold user data and tokens. Before #655 only super admins
    # could see them, in the job dashboard.
    it "shows the failed job count but not the job errors" do
      job = SolidQueue::Job.create!(queue_name: "default", class_name: "GoogleCalendarSyncJob", arguments: {}, active_job_id: SecureRandom.uuid)
      SolidQueue::FailedExecution.create!(job: job, error: { exception_class: "Signet::AuthorizationError", message: "invalid_grant", backtrace: [] })

      get admin_root_path

      failed = page.at_css("#failed-jobs")
      expect(failed.text).to include("1 failed")
      expect(failed.text).not_to include("invalid_grant")
      expect(failed.text).not_to include("Signet::AuthorizationError")
      expect(failed.text).not_to include("GoogleCalendarSyncJob")
    end

    it "hides the tools that need a higher access level" do
      get admin_root_path

      expect(response).to have_http_status(:ok)
      expect(page.at_css("#tools")).to be_nil
    end
  end
end
