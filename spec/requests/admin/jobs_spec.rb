# frozen_string_literal: true

require "rails_helper"

# The job dashboard runs on Admin::JobsBaseController. Its actions are gem
# code and never call authorize, so the base controller must not run
# verify_authorized. These examples render whole pages: a stub that stops the
# request early also skips the after_action that broke the dashboard.
RSpec.describe "Admin job dashboard", type: :request do
  # The test environment uses the test adapter, which the dashboard cannot
  # read. Point the dashboard server at Solid Queue, which reads the empty
  # solid_queue tables in the test database. Mission Control adds its Solid
  # Queue methods at boot only when the app uses Solid Queue, so add them here.
  before(:all) do
    adapter = ActiveJob::QueueAdapters::SolidQueueAdapter
    adapter.prepend(ActiveJob::QueueAdapters::SolidQueueExt) unless adapter < ActiveJob::QueueAdapters::SolidQueueExt
  end

  before do
    stub_request(:get, "https://api.github.com/repos/WITCodingClub/calendar/releases/latest")
      .to_return(status: 200, body: { tag_name: "v0.0.0" }.to_json)

    MissionControl::Jobs.applications.each do |application|
      application.servers.each do |server|
        allow(server).to receive(:queue_adapter).and_return(ActiveJob::QueueAdapters::SolidQueueAdapter.new)
      end
    end

    sign_in create(:user, :super_admin)
  end

  it "does not verify Pundit authorization" do
    callbacks = Admin::JobsBaseController._process_action_callbacks
    expect(callbacks.none? { |callback| callback.kind == :after && callback.filter == :verify_authorized }).to be(true)
  end

  %w[/admin/jobs /admin/jobs/failed/jobs /admin/jobs/applications/calendar/workers /admin/jobs/applications/calendar/recurring_tasks].each do |path|
    it "renders #{path}" do
      get path
      follow_redirect! while response.redirect? && URI.parse(response.location).path.start_with?("/admin/jobs")

      expect(response).to have_http_status(:ok)
    end
  end
end
