# frozen_string_literal: true

require "rails_helper"

# The job dashboard, Flipper, PgHero, Blazer, and the console audits can run
# jobs, change flags, read any row, or show console sessions. They need a
# super admin, not only admin access.
RSpec.describe "Admin super admin tools", type: :request do
  TOOL_PATHS = %w[/admin/jobs /admin/flipper /admin/pghero /admin/blazer /admin/audits].freeze

  # The job dashboard reads the queues through Solid Queue, but the test
  # environment has the test adapter. So a request that gets to the job
  # dashboard stops here, before the dashboard reads the queues.
  ReachedJobDashboard = Class.new(StandardError)

  before do
    stub_request(:get, "https://api.github.com/repos/WITCodingClub/calendar/releases/latest")
      .to_return(status: 200, body: { tag_name: "v0.0.0" }.to_json)

    MissionControl::Jobs.applications.each do |application|
      application.servers.each { |server| allow(server).to receive(:activating).and_raise(ReachedJobDashboard) }
    end
  end

  def open_tool(path)
    get path
    follow_redirect! while response.redirect? && URI.parse(response.location).path.start_with?(path)
  end

  context "when a plain admin is signed in" do
    before { sign_in create(:user, :admin) }

    TOOL_PATHS.each do |path|
      it "sends the admin away from #{path}" do
        get path

        expect(response).to redirect_to(dashboard_root_path)
      end
    end

    it "still opens the admin home page" do
      get admin_root_path

      expect(response).to have_http_status(:ok)
    end
  end

  %i[super_admin owner].each do |level|
    context "when a user with #{level} access is signed in" do
      before { sign_in create(:user, level) }

      it "gets to the job dashboard" do
        expect { open_tool("/admin/jobs") }.to raise_error(ReachedJobDashboard)
      end

      (TOOL_PATHS - [ "/admin/jobs" ]).each do |path|
        it "opens #{path}" do
          open_tool(path)

          expect(response).to have_http_status(:ok)
        end
      end
    end
  end
end
