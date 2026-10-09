# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendar::CalendarManager do
  subject(:manager) { described_class.new(user, rate_limiter: GoogleCalendar::Provider.new(user)) }

  let(:api)  { GoogleApiStubs::GOOGLE_CALENDAR_API }
  let(:user) { create(:user, email: "synthetic.person@wit.edu") }
  let(:credential) do
    create(:oauth_credential, user: user, email: "synthetic.person@wit.edu", access_token: "synthetic-user-token",
                              token_expires_at: 1.hour.from_now)
  end
  let(:json_headers) { { "Content-Type" => "application/json" } }

  def google_error(status)
    { status: status, body: { error: { code: status, message: "Synthetic error" } }.to_json, headers: json_headers }
  end

  before { stub_google_service_account }

  describe "#create_calendar" do
    it "creates the calendar with the service account" do
      insert = stub_request(:post, "#{api}/calendars")
               .with(headers: { "Authorization" => "Bearer synthetic-service-account-token" },
                     body: hash_including("summary" => "[TEST] WIT Courses", "timeZone" => "America/New_York"))
               .to_return(status: 200, body: { id: "synthetic-new-calendar", summary: "[TEST] WIT Courses" }.to_json, headers: json_headers)

      calendar = manager.create_calendar

      expect(insert).to have_been_requested.once
      expect(calendar.id).to eq("synthetic-new-calendar")
    end
  end

  describe "#share_with_user" do
    let(:acl_url) { "#{api}/calendars/synthetic-course-calendar/acl" }

    before { credential }

    it "adds an owner rule for each linked account" do
      share = stub_request(:post, acl_url)
              .with(query: { "sendNotifications" => "false" },
                    body: { role: "owner", scope: { type: "user", value: "synthetic.person@wit.edu" } }.to_json)
              .to_return(status: 200, body: "{}", headers: json_headers)

      manager.share_with_user("synthetic-course-calendar")

      expect(share).to have_been_requested.once
    end

    it "treats a rule that already exists as done" do
      stub_request(:post, acl_url).with(query: hash_including({})).to_return(google_error(409))

      expect { manager.share_with_user("synthetic-course-calendar") }.not_to raise_error
    end
  end

  describe "#unshare_with_email" do
    it "deletes the ACL rule with the service account" do
      removal = stub_request(:delete, google_acl_url("synthetic-course-calendar", "second@example.test"))
                .with(headers: { "Authorization" => "Bearer synthetic-service-account-token" })
                .to_return(status: 204)

      manager.unshare_with_email("synthetic-course-calendar", "second@example.test")

      expect(removal).to have_been_requested.once
    end

    it "raises any error other than a missing rule" do
      stub_request(:delete, google_acl_url("synthetic-course-calendar", "second@example.test")).to_return(google_error(403))

      expect { manager.unshare_with_email("synthetic-course-calendar", "second@example.test") }
        .to raise_error(Google::Apis::ClientError)
    end
  end

  describe "#add_to_calendar_list" do
    let(:list_url) { "#{api}/users/me/calendarList" }

    before { credential }

    it "adds the calendar to the account's list with the account's token" do
      add = stub_request(:post, list_url)
            .with(headers: { "Authorization" => "Bearer synthetic-user-token" },
                  body: hash_including("id" => "synthetic-course-calendar", "summaryOverride" => "WIT Courses", "colorId" => "7"))
            .to_return(status: 200, body: "{}", headers: json_headers)

      manager.add_to_calendar_list("synthetic-course-calendar", "synthetic.person@wit.edu")

      expect(add).to have_been_requested.once
    end

    it "does nothing for an email with no linked account" do
      manager.add_to_calendar_list("synthetic-course-calendar", "unknown@example.test")

      expect(a_request(:post, list_url)).not_to have_been_made
    end

    it "treats a calendar that is already in the list as done" do
      stub_request(:post, list_url).to_return(google_error(409))

      expect { manager.add_to_calendar_list("synthetic-course-calendar", "synthetic.person@wit.edu") }.not_to raise_error
    end

    it "tries again while the new calendar is not visible to the account" do
      allow(manager).to receive(:sleep)
      add = stub_request(:post, list_url).to_return(google_error(404), { status: 200, body: "{}", headers: json_headers })

      manager.add_to_calendar_list("synthetic-course-calendar", "synthetic.person@wit.edu")

      expect(add).to have_been_requested.twice
      expect(manager).to have_received(:sleep).with(10)
    end

    it "raises after three more tries" do
      allow(manager).to receive(:sleep)
      add = stub_request(:post, list_url).to_return(google_error(404))

      expect { manager.add_to_calendar_list("synthetic-course-calendar", "synthetic.person@wit.edu") }
        .to raise_error(Google::Apis::ClientError)
      expect(add).to have_been_requested.times(4)
    end
  end

  describe "#add_to_all_calendar_lists" do
    it "adds the calendar to the list of each linked account" do
      credential
      create(:oauth_credential, user: user, email: "second@example.test", access_token: "synthetic-second-token",
                                token_expires_at: 1.hour.from_now)
      add = stub_request(:post, "#{api}/users/me/calendarList").to_return(status: 200, body: "{}", headers: json_headers)

      described_class.new(user, rate_limiter: throttle_free_rate_limiter).add_to_all_calendar_lists("synthetic-course-calendar")

      expect(add).to have_been_requested.twice
    end
  end

  describe "#remove_from_calendar_list and #delete_calendar" do
    let(:calendar_list_url) { google_calendar_list_url("synthetic-course-calendar") }

    before { create(:course_calendar, oauth_credential: credential, external_calendar_id: "synthetic-course-calendar") }

    it "removes the calendar from the account's list" do
      removal = stub_request(:delete, calendar_list_url)
                .with(headers: { "Authorization" => "Bearer synthetic-user-token" }).to_return(status: 204)

      manager.remove_from_calendar_list("synthetic-course-calendar", "synthetic.person@wit.edu")

      expect(removal).to have_been_requested.once
    end

    it "does not raise when the removal fails" do
      stub_request(:delete, calendar_list_url).to_return(google_error(403))

      expect { manager.remove_from_calendar_list("synthetic-course-calendar", "synthetic.person@wit.edu") }.not_to raise_error
    end

    it "removes the calendar from each list, then deletes it with the service account" do
      removal  = stub_request(:delete, calendar_list_url).to_return(status: 204)
      deletion = stub_request(:delete, "#{api}/calendars/synthetic-course-calendar")
                 .with(headers: { "Authorization" => "Bearer synthetic-service-account-token" }).to_return(status: 204)

      manager.delete_calendar("synthetic-course-calendar")

      expect(removal).to have_been_requested.once
      expect(deletion).to have_been_requested.once
    end
  end

  describe "#list_calendars" do
    it "lists the service account's calendars" do
      stub_request(:get, "#{api}/users/me/calendarList")
        .to_return(status: 200, body: { items: [ { id: "synthetic-course-calendar" } ] }.to_json, headers: json_headers)

      expect(manager.list_calendars.items.map(&:id)).to eq([ "synthetic-course-calendar" ])
    end
  end

  def throttle_free_rate_limiter
    GoogleCalendar::Provider.new(user).tap do |provider|
      provider.rate_limit_config = GoogleCalendar::RateLimiter::RateLimitConfig.new.tap { |c| c.batch_throttle_delay = 0 }
    end
  end
end
