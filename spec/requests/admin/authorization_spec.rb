# frozen_string_literal: true

require "rails_helper"

# Admin::ApplicationController runs verify_authorized after every action. An
# admin action that never calls authorize or skip_authorization raises
# Pundit::AuthorizationNotPerformedError. A new admin action could skip Pundit
# and nobody would notice, so this spec requests every admin route as an owner
# and fails on that error. Each route gets a real record for its :id param, so
# the request gets past the record lookup and reaches the authorization call.
# The mounted engines (Mission Control, Flipper UI, PgHero, Blazer, Audits1984)
# have no admin/ routes, so the spec skips them. Mission Control inherits from
# Admin::JobsBaseController, which skips verify_authorized; see
# spec/requests/admin/jobs_spec.rb.
RSpec.describe "Admin authorization", type: :request do
  admin_routes = Rails.application.routes.routes.filter_map do |route|
    controller = route.defaults[:controller]
    next unless controller&.start_with?("admin/")

    verb = route.verb.split("|").first.presence || "GET"
    path = route.path.spec.to_s.delete_suffix("(.:format)")

    { controller: controller, action: route.defaults[:action], verb: verb, path: path }
  end

  let(:owner) { create(:user, access_level: :owner) }

  # The record each admin controller finds from :id.
  let(:records) do
    {
      "admin/users"                     => -> { create(:user).public_id },
      "admin/faculties"                 => -> { create(:faculty).id },
      "admin/finals_schedules"          => -> { create(:finals_schedule).tap { |schedule| attach_pdf(schedule) }.id },
      "admin/university_calendar_events" => -> { create(:university_calendar_event).id },
      "admin/courses"                   => -> { create(:course).public_id },
      "admin/rooms"                     => -> { create(:room).public_id },
      "admin/terms"                     => -> { create(:term).public_id },
      "admin/calendars"                 => -> { create(:course_calendar).id },
      "admin/buildings"                 => -> { create(:building).id }
    }
  end

  def attach_pdf(schedule)
    schedule.pdf_file.attach(io: StringIO.new("%PDF-1.4"), filename: "finals.pdf", content_type: "application/pdf")
  end

  def path_for(route)
    path = route[:path]
    record = records[route[:controller]]
    path = path.sub(":id", record.call.to_s) if record
    path.gsub(":term_uid", "202620").gsub(":public_id", "trm_none").gsub(/:\w+/, "1")
  end

  before do
    stub_request(:get, "https://api.github.com/repos/WITCodingClub/calendar/releases/latest")
      .to_return(status: 200, body: { tag_name: "v0.0.0" }.to_json)
    stub_request(:get, %r{\Ahttps://selfservice\.wit\.edu/})
      .to_return(status: 200, body: [].to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:post, %r{\Ahttps://www\.ratemyprofessors\.com/graphql})
      .to_return(status: 200, body: { data: { newSearch: { teachers: { edges: [] } } } }.to_json,
                 headers: { "Content-Type" => "application/json" })
    allow(TwentyFiveLive::SyncJob).to receive(:in_progress?).and_return(false)
    sign_in owner
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:google, :client_id).and_return("client-id")
    allow(Rails.application.credentials).to receive(:dig).with(:google, :client_secret).and_return("client-secret")
  end

  it "runs verify_authorized after every admin action" do
    callbacks = Admin::ApplicationController._process_action_callbacks
    expect(callbacks.any? { |callback| callback.kind == :after && callback.filter == :verify_authorized }).to be(true)
  end

  it "finds the admin routes" do
    expect(admin_routes.size).to be > 40
  end

  admin_routes.each do |route|
    it "authorizes #{route[:verb]} #{route[:path]} (#{route[:controller]}##{route[:action]})" do
      path = path_for(route)

      begin
        process route[:verb].downcase.to_sym, path
      rescue Pundit::AuthorizationNotPerformedError
        raise
      rescue Exception # rubocop:disable Lint/RescueException
        # A GET page must render. A write action can fail after it authorizes,
        # for example on a blocked outside request, so only a missing
        # authorization fails it.
        raise if route[:verb] == "GET"
      end
    end
  end
end
