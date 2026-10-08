# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public meeting link page", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:zone)  { Time.zone }
  let(:owner) { create(:user, first_name: "Sample", last_name: "Owner") }
  # Thursday 2026-10-08 and Friday 2026-10-09.
  let(:link)  { create(:meeting_link, user: owner, starts_on: Date.new(2026, 10, 8), ends_on: Date.new(2026, 10, 9), duration_minutes: 30) }
  let(:path)  { "/meet/#{link.token}" }
  let(:pick)  { { start_time: "2026-10-08T10:00:00-04:00", name: "Sample Guest", email: "guest@example.com" } }

  # Wednesday 2026-10-07, noon.
  around { |example| travel_to(zone.local(2026, 10, 7, 12)) { example.run } }

  before { Flipper.enable_actor(FlipperFlags::MEETING_LINKS, owner) }

  after { Flipper.disable(FlipperFlags::MEETING_LINKS) }

  def enroll(user, title:, crn:, day_of_week:, begin_time:, end_time:)
    course = create(:course, title: title, crn: crn, subject: "ZQXV", course_number: 4321)
    create(:course_meeting_time, course: course, day_of_week: day_of_week, begin_time: begin_time, end_time: end_time)
    create(:enrollment, user: user, course: course)
  end

  def offered_times
    response.body.scan(/value="(2026-10-\d\dT[\d:]+-04:00)"/).flatten
  end

  describe "GET /meet/:token" do
    it "shows the owner's free times to a guest who is not signed in" do
      get path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Book a time with Sample Owner").and include("30 minutes")
      expect(offered_times.first).to eq("2026-10-08T08:00:00-04:00")
      expect(response.body).to include("Sign in")
    end

    it "keeps the token out of the log, for the page and for a booking" do
      io     = StringIO.new
      logger = ActiveSupport::Logger.new(io)
      Rails.logger.broadcast_to(logger)

      get path
      post path, params: pick

      expect(io.string).to include('Started GET "/meet/[FILTERED]"').and include('Started POST "/meet/[FILTERED]"')
      expect(io.string).not_to include(link.token)
    ensure
      Rails.logger.stop_broadcasting_to(logger)
    end

    it "keeps the token away from other sites and search engines" do
      get path

      expect(response.headers["Referrer-Policy"]).to eq("no-referrer")
      expect(response.headers["X-Robots-Tag"]).to eq("noindex, nofollow")
    end

    it "shows no course data at all, only free times" do
      enroll(owner, title: "Synthetic Course Zeta", crn: 98_765, day_of_week: :thursday, begin_time: 1000, end_time: 1050)

      get path

      expect(response.body).not_to include("Synthetic Course Zeta")
      expect(response.body).not_to include("98765")
      expect(response.body).not_to include("ZQXV")
      expect(response.body).not_to include("4321")
      expect(offered_times).not_to include("2026-10-08T10:00:00-04:00", "2026-10-08T10:30:00-04:00")
      expect(offered_times).to include("2026-10-08T09:30:00-04:00", "2026-10-08T11:00:00-04:00")
    end

    it "shows a signed-in guest only the times when both people are free, with name and email filled in" do
      guest = create(:user, first_name: "Signed", last_name: "Guest")
      enroll(guest, title: "Synthetic Guest Course", crn: 98_766, day_of_week: :thursday, begin_time: 800, end_time: 1150)
      sign_in guest

      get path

      expect(offered_times.first).to eq("2026-10-08T12:00:00-04:00")
      expect(response.body).to include(%(value="#{guest.email}")).and include(%(value="Signed Guest"))
      expect(response.body).not_to include("Synthetic Guest Course")
    end

    it "tells the owner that the link is their own, with no booking form" do
      sign_in owner

      get path

      expect(response.body).to include("This is your own link")
      expect(response.body).not_to include("Book this time")
    end

    it "gives the same 404 page for an unknown, expired, used, or revoked link, and when the owner has no flag" do
      get "/meet/not-a-real-token"
      unknown = response.body
      expect(response).to have_http_status(:not_found)
      expect(unknown).to include("This link no longer works")

      [ create(:meeting_link, :expired, user: owner), create(:meeting_link, :used, user: owner),
        create(:meeting_link, :revoked, user: owner) ].each do |gone|
        get "/meet/#{gone.token}"
        expect(response).to have_http_status(:not_found)
        expect(response.body).to eq(unknown)
      end

      Flipper.disable(FlipperFlags::MEETING_LINKS)
      get path
      expect(response).to have_http_status(:not_found)
      expect(response.body).to eq(unknown)
    end
  end

  describe "POST /meet/:token" do
    let(:events_url) { "#{GoogleApiStubs::GOOGLE_CALENDAR_API}/calendars/synthetic-course-calendar/events" }

    before do
      credential = create(:oauth_credential, user: owner, access_token: "synthetic-user-token", token_expires_at: 1.hour.from_now)
      create(:course_calendar, oauth_credential: credential, external_calendar_id: "synthetic-course-calendar")
    end

    it "books the time, puts it in the owner's Google calendar with the guest invited, and shows a confirmation" do
      google = stub_request(:post, events_url)
               .with(query: { "sendUpdates" => "all" }) { |request| JSON.parse(request.body)["attendees"] == [ { "displayName" => "Sample Guest", "email" => "guest@example.com" } ] }
               .to_return(status: 200, body: file_fixture("google_calendar/event_created.json").read, headers: { "Content-Type" => "application/json" })

      perform_enqueued_jobs { post path, params: pick }

      expect(response).to redirect_to(path)
      expect(google).to have_been_requested.once
      expect(ActionMailer::Base.deliveries.map(&:to)).to include([ "guest@example.com" ])
      expect(link.reload).to be_used

      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Your meeting is booked").and include("10:00 AM to 10:30 AM EDT")
    end

    it "refuses a second pick, and another browser sees the link as gone" do
      post path, params: pick
      post path, params: pick.merge(start_time: "2026-10-08T11:00:00-04:00", email: "other@example.com")

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("This link no longer works")
      expect(FriendMeeting.count).to eq(1)

      reset!
      get path
      expect(response).to have_http_status(:not_found)
    end

    it "shows the reason and the times again when the time is not free" do
      enroll(owner, title: "Synthetic Course Zeta", crn: 98_765, day_of_week: :thursday, begin_time: 1000, end_time: 1050)

      post path, params: pick

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("That time is no longer free")
      expect(response.body).not_to include("Synthetic Course Zeta")
      expect(link.reload).to be_usable
    end

    it "keeps the signed-in guest on the link" do
      guest = create(:user)
      sign_in guest

      post path, params: pick

      expect(link.reload.guest_user).to eq(guest)
    end

    it "does not let the owner book their own link" do
      sign_in owner

      post path, params: pick

      expect(response).to redirect_to(path)
      expect(link.reload).to be_usable
    end
  end

  describe "signing in from the link" do
    before do
      OmniAuth.config.test_mode = true
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider:    "google_oauth2",
        uid:         "google-uid-guest",
        info:        { email: "signed.guest@wit.edu", first_name: "Signed", last_name: "Guest" },
        credentials: { token: "synthetic-access-token", expires_at: 1.hour.from_now.to_i },
        extra:       { raw_info: { granted_scopes: "email profile" } }
      )
    end

    after do
      OmniAuth.config.mock_auth[:google_oauth2] = nil
      OmniAuth.config.test_mode = false
    end

    it "sends the guest to sign in, then back to the link" do
      get "#{path}/sign_in"
      expect(response).to redirect_to(new_user_session_path)

      get "/auth/google_oauth2/callback"
      expect(response).to redirect_to(path)

      get "/auth/google_oauth2/callback"
      expect(response).to redirect_to(dashboard_root_path)
    end
  end
end
