# frozen_string_literal: true

require "rails_helper"

# How GoogleCalendar::Provider writes one schedule event: the create, update
# and delete steps of CourseCalendars::Provider with the Google remote calls.
# The examples call update_specific_events and delete_events.
RSpec.describe GoogleCalendar::Provider do
  subject(:provider) { described_class.new(user) }

  let(:zone)       { Time.find_zone!("America/New_York") }
  let(:user)       { create(:user) }
  let(:credential) { create(:oauth_credential, user: user, access_token: "synthetic-user-token", token_expires_at: 1.hour.from_now) }
  let!(:calendar) { create(:course_calendar, oauth_credential: credential, external_calendar_id: "synthetic-course-calendar") }
  let(:events_url) { "#{GoogleApiStubs::GOOGLE_CALENDAR_API}/calendars/synthetic-course-calendar/events" }
  let(:json)       { { status: 200, body: file_fixture("google_calendar/event_created.json").read, headers: { "Content-Type" => "application/json" } } }
  let(:start)      { zone.local(2026, 9, 15, 15) }
  let(:university_event) { create(:university_calendar_event) }
  let(:event_data) do
    CourseCalendars::Event.new(source: university_event, summary: "Synthetic Lecture", location: "Synthetic Hall",
                               start_time: start, end_time: start + 1.hour)
  end

  # A calendar without event labels, so a color goes out as a legacy colorId.
  before do
    allow(GoogleCalendar::EventLabels).to receive(:new)
      .and_return(instance_double(GoogleCalendar::EventLabels, available?: false, label_id_for: nil))
  end

  # Each example goes through the public sync entry points.
  # update_specific_events makes or updates the given events and deletes
  # nothing, so it shows the create and update steps one event at a time.
  def sync(event, force: false)
    provider.update_specific_events([ event ], force: force)
  end

  def google_error(status)
    { status: status, body: { error: { code: status, message: "Synthetic error" } }.to_json, headers: { "Content-Type" => "application/json" } }
  end

  describe "#create" do
    it "inserts the event and tracks it with a row" do
      insert = stub_request(:post, events_url)
               .with(headers: { "Authorization" => "Bearer synthetic-user-token" },
                     body: hash_including("summary" => "Synthetic Lecture", "location" => "Synthetic Hall"))
               .to_return(json)

      expect(sync(event_data)).to include(created: 1)

      expect(insert).to have_been_requested.once
      expect(calendar.calendar_events.sole).to have_attributes(external_event_id: "syntheticmeetingevent1", summary: "Synthetic Lecture",
                                     university_calendar_event_id: university_event.id, meeting_time_id: nil,
                                     event_data_hash: event_data.data_hash)
    end

    it "asks Google to read the event label" do
      labels = instance_double(GoogleCalendar::EventLabels, available?: true, label_id_for: "11111111-2222-3333-4444-555555555555")
      insert = stub_request(:post, events_url).with(query: { "eventLabelVersion" => "1" },
                                                    body: hash_including("eventLabelId" => "11111111-2222-3333-4444-555555555555"))
                                              .to_return(json)

      allow(GoogleCalendar::EventLabels).to receive(:new).and_return(labels)

      sync(event_data.with(color_id: "#1a2b3c"))

      expect(insert).to have_been_requested.once
    end

    it "deletes the new event when the unique index refuses its row" do
      # A parallel sync saved the same source between this row's check and its insert.
      allow(CalendarEvent).to receive(:new).and_wrap_original do |original, *args, **options, &block|
        original.call(*args, **options, &block).tap do |record|
          allow(record).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique)
        end
      end
      stub_request(:post, events_url).to_return(json)
      delete = stub_request(:delete, "#{events_url}/syntheticmeetingevent1").with(query: { "sendUpdates" => "none" }).to_return(status: 204)

      sync(event_data)

      expect(delete).to have_been_requested.once
    end

    it "deletes the new event when a concurrent sync already tracks it" do
      # The other sync tracks the event while this one waits for Google.
      stub_request(:post, events_url).to_return do
        create(:calendar_event, :for_university_event, course_calendar: calendar, university_calendar_event: university_event,
                                                       external_event_id: "synthetic-other-sync")
        json
      end
      delete = stub_request(:delete, "#{events_url}/syntheticmeetingevent1").with(query: { "sendUpdates" => "none" }).to_return(status: 204)

      expect(sync(event_data)).to include(created: 0, skipped: 1)

      expect(delete).to have_been_requested.once
      expect(calendar.calendar_events.sole.external_event_id).to eq("synthetic-other-sync")
    end

    it "deletes the new event when the other sync's row lands between the validation and the insert" do
      stub_request(:post, events_url).to_return(json)
      delete = stub_request(:delete, "#{events_url}/syntheticmeetingevent1").with(query: { "sendUpdates" => "none" }).to_return(status: 204)
      other_sync = false
      allow_any_instance_of(CalendarEvent).to receive(:valid?).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
        original.call(*args).tap do
          next if other_sync

          other_sync = true
          create(:calendar_event, :for_university_event, course_calendar: calendar, university_calendar_event: university_event,
                                                         external_event_id: "synthetic-other-sync")
        end
      end

      expect(sync(event_data)).to include(created: 0, skipped: 1)

      expect(delete).to have_been_requested.once
      expect(calendar.calendar_events.sole.external_event_id).to eq("synthetic-other-sync")
    end

    it "reports a failed delete of the duplicate and finishes the sync" do
      stub_request(:post, events_url).to_return do
        create(:calendar_event, :for_university_event, course_calendar: calendar, university_calendar_event: university_event)
        json
      end
      stub_request(:delete, "#{events_url}/syntheticmeetingevent1").with(query: hash_including({})).to_return(google_error(500))
      allow(Rails.error).to receive(:report)

      expect(sync(event_data)).to include(created: 0, skipped: 1)

      expect(Rails.error).to have_received(:report)
        .with(instance_of(Google::Apis::ServerError), handled: true,
                                                      context: { user_id: user.id, calendar_id: calendar.id, external_event_id: "syntheticmeetingevent1" })
    end

    it "raises a validation error that is not a taken source and keeps the event" do
      stub_request(:post, events_url).to_return(json.merge(body: { summary: "Synthetic Lecture" }.to_json))

      expect { sync(event_data) }.to raise_error(ActiveRecord::RecordInvalid, /External event/)

      expect(a_request(:delete, /googleapis/)).not_to have_been_made
    end
  end

  describe "#update" do
    let(:event_url) { "#{events_url}/synthetic-event" }
    let!(:row) do
      create(:calendar_event, :for_university_event, course_calendar: calendar, university_calendar_event: university_event,
                                                     external_event_id: "synthetic-event", summary: "Old Lecture",
                                                     location: "Synthetic Hall", start_time: start, end_time: start + 1.hour)
    end

    def remote_body(**overrides)
      { status: 200, headers: { "Content-Type" => "application/json" },
        body: { id: "synthetic-event", summary: "Old Lecture", location: "Synthetic Hall",
                start: { dateTime: start.iso8601 }, end: { dateTime: (start + 1.hour).iso8601 } }.merge(overrides).to_json }
    end

    it "marks an unchanged event as synced without a request" do
      row.update!(event_data_hash: event_data.data_hash)

      expect(sync(event_data)).to include(skipped: 1, updated: 0)
      expect(a_request(:any, /googleapis/)).not_to have_been_made
    end

    it "updates an event when only the description changed" do
      row.update!(event_data_hash: event_data.with(description: "Prof. Example").data_hash)
      stub_request(:get, event_url).to_return(remote_body)
      put = stub_request(:put, event_url).with(body: hash_including("description" => "Prof. Other")).to_return(json)

      expect(sync(event_data.with(description: "Prof. Other"))).to include(updated: 1)
      expect(put).to have_been_requested.once
    end

    it "writes the new data over an event the person did not edit" do
      stub_request(:get, event_url).to_return(remote_body)
      put = stub_request(:put, event_url).with(body: hash_including("summary" => "Synthetic Lecture")).to_return(json)

      expect(sync(event_data)).to include(updated: 1)
      expect(put).to have_been_requested.once
      expect(row.reload).to have_attributes(summary: "Synthetic Lecture", user_edited_fields: nil)
    end

    it "keeps a field the person edited in Google" do
      stub_request(:get, event_url).to_return(remote_body(location: "My Own Room"))
      put = stub_request(:put, event_url).with(body: hash_including("summary" => "Synthetic Lecture", "location" => "My Own Room"))
                                         .to_return(json)

      sync(event_data)

      expect(put).to have_been_requested.once
      expect(row.reload).to have_attributes(location: "My Own Room", user_edited_fields: [ "location" ])
    end

    it "makes no request on the next sync of an event the person edited" do
      stub_request(:get, event_url).to_return(remote_body(location: "My Own Room"))
      stub_request(:put, event_url).to_return(json)
      sync(event_data)
      WebMock.reset_executed_requests!

      expect(sync(event_data)).to include(skipped: 1, updated: 0)
      expect(a_request(:any, /googleapis/)).not_to have_been_made
    end

    it "keeps the whole event when the person edited the recurrence" do
      stub_request(:get, event_url).to_return(remote_body(recurrence: [ "RRULE:FREQ=WEEKLY;BYDAY=TU" ]))

      expect(sync(event_data)).to include(skipped: 1, updated: 0)
      expect(a_request(:put, event_url)).not_to have_been_made
      expect(row.reload).to have_attributes(summary: "Old Lecture", recurrence: nil)
    end

    it "keeps the person's recurrence on every later sync" do
      row.update!(recurrence: [ "RRULE:FREQ=WEEKLY;BYDAY=TU" ])
      data = event_data.with(recurrence: CourseCalendars::Recurrence.parse([ "RRULE:FREQ=WEEKLY;BYDAY=TU" ]))
      stub_request(:get, event_url).to_return(remote_body(recurrence: [ "RRULE:FREQ=WEEKLY;BYDAY=TH" ]))

      expect(sync(data)).to include(skipped: 1, updated: 0)
      expect(sync(data)).to include(skipped: 1, updated: 0)
      expect(a_request(:put, event_url)).not_to have_been_made
    end

    it "writes a new description over the one the app wrote before" do
      row.update!(user_edited_fields: [ "description" ])
      stub_request(:get, event_url).to_return(remote_body(description: "CRN 10001"))
      put = stub_request(:put, event_url).with(body: hash_including("description" => "CRN 20002")).to_return(json)

      sync(event_data.with(description: "CRN 20002"))

      expect(put).to have_been_requested.once
      expect(row.reload.user_edited_fields).to be_nil
    end

    context "with an all-day event" do
      let(:day) { zone.local(2026, 11, 26) }
      let!(:row) do
        create(:calendar_event, :for_university_event, course_calendar: calendar, university_calendar_event: university_event,
                                                       external_event_id: "synthetic-event", summary: "Old Holiday",
                                                       location: nil, start_time: day, end_time: day.end_of_day)
      end
      let(:holiday_data) do
        CourseCalendars::Event.new(source: university_event, summary: "Synthetic Holiday", start_time: day,
                                   end_time: day.end_of_day, all_day: true)
      end

      def all_day_body(start_date, end_date)
        remote_body(summary: "Old Holiday", location: nil, start: { date: start_date }, end: { date: end_date })
      end

      it "keeps the same days when the person did not move the event" do
        stub_request(:get, event_url).to_return(all_day_body("2026-11-26", "2026-11-27"))
        put = stub_request(:put, event_url).with(body: hash_including("start" => { "date" => "2026-11-26" },
                                                                      "end"   => { "date" => "2026-11-27" }))
                                           .to_return(json)

        expect(sync(holiday_data)).to include(updated: 1)
        expect(put).to have_been_requested.once
        expect(row.reload.user_edited_fields).to be_nil
      end

      it "keeps the last day the person chose" do
        stub_request(:get, event_url).to_return(all_day_body("2026-11-26", "2026-11-28"))
        put = stub_request(:put, event_url).with(body: hash_including("end" => { "date" => "2026-11-28" })).to_return(json)

        sync(holiday_data)

        expect(put).to have_been_requested.once
        expect(row.reload.user_edited_fields).to eq([ "end_time" ])
      end
    end

    it "makes an event that is gone from Google again" do
      stub_request(:get, event_url).to_return(google_error(404))
      insert = stub_request(:post, events_url).with(body: hash_including("summary" => "Synthetic Lecture")).to_return(json)

      expect(sync(event_data)).to include(updated: 1)
      expect(insert).to have_been_requested.once
      expect(calendar.calendar_events.sole.external_event_id).to eq("syntheticmeetingevent1")
    end

    it "counts an event that a concurrent sync made again first as skipped" do
      stub_request(:get, event_url).to_return(google_error(404))
      stub_request(:post, events_url).to_return do
        create(:calendar_event, :for_university_event, course_calendar: calendar, university_calendar_event: university_event,
                                                       external_event_id: "synthetic-other-sync")
        json
      end
      delete = stub_request(:delete, "#{events_url}/syntheticmeetingevent1").with(query: { "sendUpdates" => "none" }).to_return(status: 204)

      expect(sync(event_data)).to include(updated: 0, skipped: 1)
      expect(delete).to have_been_requested.once
      expect(calendar.calendar_events.sole.external_event_id).to eq("synthetic-other-sync")
    end

    [ 404, 410 ].each do |status|
      it "with force, makes the event again when Google answers #{status}" do
        stub_request(:put, event_url).to_return(google_error(status))
        insert = stub_request(:post, events_url).with(body: hash_including("summary" => "Synthetic Lecture")).to_return(json)

        expect(sync(event_data, force: true)).to include(updated: 1)
        expect(insert).to have_been_requested.once
        expect(calendar.calendar_events.sole.external_event_id).to eq("syntheticmeetingevent1")
      end
    end

    it "with force, writes over the person's edits without reading the event" do
      row.update!(user_edited_fields: [ "location" ])
      put = stub_request(:put, event_url).with(body: hash_including("location" => "Synthetic Hall")).to_return(json)

      expect(sync(event_data, force: true)).to include(updated: 1)
      expect(put).to have_been_requested.once
      expect(row.reload.user_edited_fields).to be_nil
    end
  end

  describe "#delete" do
    let(:row) { create(:calendar_event, :for_university_event, course_calendar: calendar, external_event_id: "synthetic-event") }

    it "deletes the event and the row" do
      delete = stub_request(:delete, "#{events_url}/synthetic-event").to_return(status: 204)

      provider.delete_events([ row ])

      expect(delete).to have_been_requested.once
      expect(CalendarEvent.exists?(row.id)).to be(false)
    end

    it "deletes only the row of an event that Google already deleted" do
      stub_request(:delete, "#{events_url}/synthetic-event").to_return(google_error(410))

      provider.delete_events([ row ])

      expect(CalendarEvent.exists?(row.id)).to be(false)
    end

    it "raises any other error and keeps the row" do
      stub_request(:delete, "#{events_url}/synthetic-event").to_return(google_error(403))

      expect { provider.delete_events([ row ]) }.to raise_error(Google::Apis::ClientError)
      expect(CalendarEvent.exists?(row.id)).to be(true)
    end
  end
end
