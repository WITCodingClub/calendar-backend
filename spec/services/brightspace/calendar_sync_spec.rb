# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Brightspace deadline calendar sync" do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:connection) { create(:brightspace_connection, user: user) }
  let(:offering) { create(:brightspace_course_offering, connection: connection, title: "Data Structures") }

  before { Flipper.enable_actor(FlipperFlags::BRIGHTSPACE, user) }

  describe "User#build_brightspace_events_for_sync" do
    it "builds a zero-length event at the effective deadline" do
      due = 2.days.from_now.change(usec: 0)
      assignment = create(:brightspace_assignment, course_offering: offering, title: "Lab 4", due_at: 5.days.from_now, user_due_at: due)

      events = user.build_brightspace_events_for_sync

      expect(events).to contain_exactly(
        hash_including(summary: "Lab 4", description: "Data Structures", start_time: due, end_time: due,
                       brightspace_assignment_id: assignment.id, all_day: false)
      )
    end

    it "uses the personal override" do
      assignment = create(:brightspace_assignment, course_offering: offering, due_at: 5.days.from_now)
      override = 1.day.from_now.change(usec: 0)
      create(:brightspace_assignment_preference, assignment: assignment, due_at_override: override)

      expect(user.build_brightspace_events_for_sync.sole[:start_time]).to eq(override)
    end

    it "never uses the open or close date as the deadline" do
      create(:brightspace_assignment, course_offering: offering, due_at: nil, opens_at: 1.day.from_now, closes_at: 3.days.from_now)

      expect(user.build_brightspace_events_for_sync).to eq([])
    end

    it "skips removed work, past work, and the work of a disconnected account" do
      create(:brightspace_assignment, :removed, course_offering: offering)
      past = create(:brightspace_assignment, course_offering: offering, due_at: 1.day.ago)

      expect(user.build_brightspace_events_for_sync).to eq([])
      expect(user.build_brightspace_events_for_sync(time_scope: :past).pluck(:brightspace_assignment_id)).to eq([ past.id ])

      create(:brightspace_assignment, course_offering: offering)
      connection.disconnect!
      expect(user.build_brightspace_events_for_sync).to eq([])
    end

    it "follows the class preference" do
      create(:brightspace_assignment, course_offering: offering, kind: "assignment")
      quiz = create(:brightspace_assignment, course_offering: offering, kind: "quiz")
      preference = create(:brightspace_class_preference, course_offering: offering, included_kinds: [ "quiz" ])

      expect(user.build_brightspace_events_for_sync.pluck(:brightspace_assignment_id)).to eq([ quiz.id ])

      preference.update!(sync_enabled: false)
      expect(user.build_brightspace_events_for_sync).to eq([])
    end

    it "builds nothing while the flag is off" do
      create(:brightspace_assignment, course_offering: offering)
      Flipper.disable_actor(FlipperFlags::BRIGHTSPACE, user)

      expect(user.build_brightspace_events_for_sync).to eq([])
    end
  end

  describe "GoogleCalendarService#update_calendar_events" do
    let(:credential) do
      create(:oauth_credential, user: user, access_token: "synthetic-user-token", refresh_token: "synthetic-user-refresh",
                                token_expires_at: 1.hour.from_now)
    end
    let!(:course_calendar) { create(:course_calendar, oauth_credential: credential, external_calendar_id: "synthetic-course-calendar") }
    let(:events_url) { "#{GoogleApiStubs::GOOGLE_CALENDAR_API}/calendars/synthetic-course-calendar/events" }
    let(:assignment) { create(:brightspace_assignment, course_offering: offering, title: "Lab 4", due_at: 2.days.from_now.change(usec: 0)) }

    before do
      allow_any_instance_of(GoogleEventLabels).to receive(:available?).and_return(false) # rubocop:disable RSpec/AnyInstance
    end

    def sync = GoogleCalendarService.new(user).update_calendar_events(user.build_brightspace_events_for_sync)

    it "creates one event, then moves it when the deadline changes" do
      insert = stub_request(:post, %r{\A#{Regexp.escape(events_url)}})
        .to_return(status: 200, body: { id: "synthetic-deadline" }.to_json, headers: { "Content-Type" => "application/json" })
      assignment

      sync

      expect(insert).to have_been_requested.once
      row = course_calendar.calendar_events.sole
      expect(row).to have_attributes(brightspace_assignment_id: assignment.id, start_time: assignment.due_at)

      # Google still holds the event as the first sync wrote it.
      stored = { id: "synthetic-deadline", summary: row.summary, location: row.location,
                 start: { dateTime: row.start_time.iso8601 }, end: { dateTime: row.end_time.iso8601 } }
      stub_request(:get, "#{events_url}/synthetic-deadline")
        .to_return(status: 200, body: stored.to_json, headers: { "Content-Type" => "application/json" })
      update = stub_request(:put, %r{\A#{Regexp.escape(events_url)}/synthetic-deadline})
        .to_return(status: 200, body: { id: "synthetic-deadline" }.to_json, headers: { "Content-Type" => "application/json" })
      assignment.update!(user_due_at: 4.days.from_now.change(usec: 0))

      sync

      expect(update).to have_been_requested.once
      expect(course_calendar.calendar_events.sole.start_time).to eq(assignment.user_due_at)
    end

    it "sends no reminders for submitted work" do
      assignment.update!(submission_status: "submitted")
      insert = stub_request(:post, %r{\A#{Regexp.escape(events_url)}})
        .with { |request| JSON.parse(request.body)["reminders"] == { "overrides" => [], "useDefault" => false } }
        .to_return(status: 200, body: { id: "synthetic-deadline" }.to_json, headers: { "Content-Type" => "application/json" })

      sync

      expect(insert).to have_been_requested.once
    end

    it "deletes the event of removed work" do
      row = create(:calendar_event, :for_brightspace_assignment, brightspace_assignment: assignment, course_calendar: course_calendar,
                                                                  external_event_id: "synthetic-deadline", start_time: assignment.due_at)
      assignment.update!(removed_at: Time.current)
      removal = stub_request(:delete, "#{events_url}/synthetic-deadline").to_return(status: 204)

      sync

      expect(removal).to have_been_requested.once
      expect(CalendarEvent.exists?(row.id)).to be(false)
    end
  end
end
