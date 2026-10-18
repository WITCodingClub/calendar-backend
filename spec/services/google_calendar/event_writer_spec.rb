# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendar::EventWriter do
  subject(:writer) { described_class.new(user, rate_limiter: GoogleCalendar::Provider.new(user)) }

  let(:zone)       { Time.find_zone!("America/New_York") }
  let(:user)       { create(:user) }
  let(:credential) { create(:oauth_credential, user: user, access_token: "synthetic-user-token", token_expires_at: 1.hour.from_now) }
  let!(:calendar) { create(:course_calendar, oauth_credential: credential, external_calendar_id: "synthetic-course-calendar") }
  let(:service)    { GoogleCalendar::CalendarServices.for_user(user) }
  let(:events_url) { "#{GoogleApiStubs::GOOGLE_CALENDAR_API}/calendars/synthetic-course-calendar/events" }
  let(:json)       { { status: 200, body: file_fixture("google_calendar/event_created.json").read, headers: { "Content-Type" => "application/json" } } }
  let(:start)      { zone.local(2026, 9, 15, 15) }
  let(:university_event) { create(:university_calendar_event) }
  let(:event_data) do
    { summary: "Synthetic Lecture", location: "Synthetic Hall", start_time: start, end_time: start + 1.hour,
      university_calendar_event_id: university_event.id }
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

      row = writer.create(service, calendar, event_data, event_data)

      expect(insert).to have_been_requested.once
      expect(row).to have_attributes(external_event_id: "syntheticmeetingevent1", summary: "Synthetic Lecture",
                                     university_calendar_event_id: university_event.id, meeting_time_id: nil,
                                     event_data_hash: CalendarEvent.generate_data_hash(event_data))
    end

    it "asks Google to read the event label" do
      labels = instance_double(GoogleCalendar::EventLabels, available?: true, label_id_for: "11111111-2222-3333-4444-555555555555")
      insert = stub_request(:post, events_url).with(query: { "eventLabelVersion" => "1" },
                                                    body: hash_including("eventLabelId" => "11111111-2222-3333-4444-555555555555"))
                                              .to_return(json)

      writer.create(service, calendar, event_data, event_data.merge(color_id: "#1a2b3c"), labels: labels)

      expect(insert).to have_been_requested.once
    end

    it "deletes the new event when a concurrent sync already tracks it" do
      allow(calendar.calendar_events).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)
      stub_request(:post, events_url).to_return(json)
      delete = stub_request(:delete, "#{events_url}/syntheticmeetingevent1").to_return(status: 204)

      expect(writer.create(service, calendar, event_data, event_data)).to be_nil
      expect(delete).to have_been_requested.once
    end
  end

  describe "#update" do
    let(:event_url) { "#{events_url}/synthetic-event" }
    let(:row) do
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
      row.update!(event_data_hash: CalendarEvent.generate_data_hash(event_data))

      expect(writer.update(service, calendar, row, event_data)).to eq(:skipped_no_change)
      expect(a_request(:any, /googleapis/)).not_to have_been_made
    end

    it "writes the new data over an event the person did not edit" do
      stub_request(:get, event_url).to_return(remote_body)
      put = stub_request(:put, event_url).with(body: hash_including("summary" => "Synthetic Lecture")).to_return(json)

      expect(writer.update(service, calendar, row, event_data)).to eq(:updated)
      expect(put).to have_been_requested.once
      expect(row.reload).to have_attributes(summary: "Synthetic Lecture", user_edited_fields: nil)
    end

    it "keeps a field the person edited in Google" do
      stub_request(:get, event_url).to_return(remote_body(location: "My Own Room"))
      put = stub_request(:put, event_url).with(body: hash_including("summary" => "Synthetic Lecture", "location" => "My Own Room"))
                                         .to_return(json)

      writer.update(service, calendar, row, event_data)

      expect(put).to have_been_requested.once
      expect(row.reload).to have_attributes(location: "My Own Room", user_edited_fields: [ "location" ])
    end

    it "keeps the whole event when the person edited the recurrence" do
      stub_request(:get, event_url).to_return(remote_body(recurrence: [ "RRULE:FREQ=WEEKLY;BYDAY=TU" ]))

      expect(writer.update(service, calendar, row, event_data)).to eq(:skipped_user_edit)
      expect(a_request(:put, event_url)).not_to have_been_made
      expect(row.reload).to have_attributes(summary: "Old Lecture", recurrence: nil)
    end

    it "keeps the person's recurrence on every later sync" do
      row.update!(recurrence: [ "RRULE:FREQ=WEEKLY;BYDAY=TU" ])
      data = event_data.merge(recurrence: [ "RRULE:FREQ=WEEKLY;BYDAY=TU" ])
      stub_request(:get, event_url).to_return(remote_body(recurrence: [ "RRULE:FREQ=WEEKLY;BYDAY=TH" ]))

      expect(writer.update(service, calendar, row, data)).to eq(:skipped_user_edit)
      expect(writer.update(service, calendar, row.reload, data)).to eq(:skipped_user_edit)
      expect(a_request(:put, event_url)).not_to have_been_made
    end

    it "writes a new description over the one the app wrote before" do
      row.update!(user_edited_fields: [ "description" ])
      stub_request(:get, event_url).to_return(remote_body(description: "CRN 10001"))
      put = stub_request(:put, event_url).with(body: hash_including("description" => "CRN 20002")).to_return(json)

      writer.update(service, calendar, row, event_data.merge(description: "CRN 20002"))

      expect(put).to have_been_requested.once
      expect(row.reload.user_edited_fields).to be_nil
    end

    context "with an all-day event" do
      let(:day) { zone.local(2026, 11, 26) }
      let(:row) do
        create(:calendar_event, :for_university_event, course_calendar: calendar, university_calendar_event: university_event,
                                                       external_event_id: "synthetic-event", summary: "Old Holiday",
                                                       location: nil, start_time: day, end_time: day.end_of_day)
      end
      let(:holiday_data) do
        { summary: "Synthetic Holiday", location: nil, start_time: day, end_time: day.end_of_day, all_day: true,
          university_calendar_event_id: university_event.id }
      end

      def all_day_body(start_date, end_date)
        remote_body(summary: "Old Holiday", location: nil, start: { date: start_date }, end: { date: end_date })
      end

      it "keeps the same days when the person did not move the event" do
        stub_request(:get, event_url).to_return(all_day_body("2026-11-26", "2026-11-27"))
        put = stub_request(:put, event_url).with(body: hash_including("start" => { "date" => "2026-11-26" },
                                                                      "end"   => { "date" => "2026-11-27" }))
                                           .to_return(json)

        expect(writer.update(service, calendar, row, holiday_data)).to eq(:updated)
        expect(put).to have_been_requested.once
        expect(row.reload.user_edited_fields).to be_nil
      end

      it "keeps the last day the person chose" do
        stub_request(:get, event_url).to_return(all_day_body("2026-11-26", "2026-11-28"))
        put = stub_request(:put, event_url).with(body: hash_including("end" => { "date" => "2026-11-28" })).to_return(json)

        writer.update(service, calendar, row, holiday_data)

        expect(put).to have_been_requested.once
        expect(row.reload.user_edited_fields).to eq([ "end_time" ])
      end
    end

    it "makes an event that is gone from Google again" do
      stub_request(:get, event_url).to_return(google_error(404))
      insert = stub_request(:post, events_url).with(body: hash_including("summary" => "Synthetic Lecture")).to_return(json)

      expect(writer.update(service, calendar, row, event_data)).to eq(:recreated)
      expect(insert).to have_been_requested.once
      expect(calendar.calendar_events.sole.external_event_id).to eq("syntheticmeetingevent1")
    end

    [ 404, 410 ].each do |status|
      it "with force, makes the event again when Google answers #{status}" do
        stub_request(:put, event_url).to_return(google_error(status))
        insert = stub_request(:post, events_url).with(body: hash_including("summary" => "Synthetic Lecture")).to_return(json)

        expect(writer.update(service, calendar, row, event_data, force: true)).to eq(:recreated)
        expect(insert).to have_been_requested.once
        expect(calendar.calendar_events.sole.external_event_id).to eq("syntheticmeetingevent1")
      end
    end

    it "with force, writes over the person's edits without reading the event" do
      row.update!(user_edited_fields: [ "location" ])
      put = stub_request(:put, event_url).with(body: hash_including("location" => "Synthetic Hall")).to_return(json)

      expect(writer.update(service, calendar, row, event_data, force: true)).to eq(:updated)
      expect(put).to have_been_requested.once
      expect(row.reload.user_edited_fields).to be_nil
    end
  end

  describe "#delete" do
    let(:row) { create(:calendar_event, :for_university_event, course_calendar: calendar, external_event_id: "synthetic-event") }

    it "deletes the event and the row" do
      delete = stub_request(:delete, "#{events_url}/synthetic-event").to_return(status: 204)

      writer.delete(service, calendar, row)

      expect(delete).to have_been_requested.once
      expect(CalendarEvent.exists?(row.id)).to be(false)
    end

    it "deletes only the row of an event that Google already deleted" do
      stub_request(:delete, "#{events_url}/synthetic-event").to_return(google_error(410))

      writer.delete(service, calendar, row)

      expect(CalendarEvent.exists?(row.id)).to be(false)
    end

    it "raises any other error and keeps the row" do
      stub_request(:delete, "#{events_url}/synthetic-event").to_return(google_error(403))

      expect { writer.delete(service, calendar, row) }.to raise_error(Google::Apis::ClientError)
      expect(CalendarEvent.exists?(row.id)).to be(true)
    end
  end
end
