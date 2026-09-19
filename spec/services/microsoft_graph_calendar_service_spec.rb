# frozen_string_literal: true

require "rails_helper"

RSpec.describe MicrosoftGraphCalendarService, :microsoft_graph do
  include ActiveSupport::Testing::TimeHelpers

  subject(:service) { described_class.new(user) }

  let(:graph)        { MicrosoftGraphHelpers::GRAPH_URL }
  let(:user)         { create(:user) }
  let(:credential)   { create(:oauth_credential, :microsoft, user: user, token_expires_at: 1.hour.from_now) }
  let(:calendar)     { create(:course_calendar, :microsoft, oauth_credential: credential, external_calendar_id: "AAMkSyntheticCalendar1") }
  let(:meeting_time) { create(:course_meeting_time) }
  let(:zone)         { Time.find_zone!("America/New_York") }

  let(:class_event) do
    {
      summary:         "Synthetic Course",
      description:     "COMP-1000-01",
      location:        "Synthetic Hall - 101",
      start_time:      zone.local(2026, 9, 14, 9, 0),
      end_time:        zone.local(2026, 9, 14, 10, 15),
      meeting_time_id: meeting_time.id,
      recurrence:      nil,
      all_day:         false
    }
  end

  let(:created_event_id) { "AAMkSyntheticEvent1" }
  let(:created_ical_uid) { JSON.parse(graph_fixture("event_created"))["iCalUId"] }

  around { |example| travel_to(zone.local(2026, 9, 1, 12, 0)) { example.run } }

  # Course events carry a color, so a sync reads the master category list.
  let!(:master_categories) do
    stub_request(:get, "#{graph}/me/outlook/masterCategories").with(query: hash_including({}))
      .to_return(graph_json_response("master_categories"))
  end
  let!(:category_create) do
    stub_request(:post, "#{graph}/me/outlook/masterCategories").to_return(graph_json_response("master_category_created", status: 201))
  end

  def stub_event_create
    stub_request(:post, "#{graph}/me/calendars/AAMkSyntheticCalendar1/events").to_return(graph_json_response("event_created"))
  end

  describe "#create_or_get_course_calendar" do
    it "creates the calendar in the mailbox and tracks it" do
      credential
      stub = stub_request(:post, "#{graph}/me/calendars")
             .with(body: hash_including("name" => "[TEST] WIT Courses"))
             .to_return(graph_json_response("calendar_created"))

      expect(service.create_or_get_course_calendar).to eq("AAMkSyntheticCalendarNew")
      expect(stub).to have_been_requested
      expect(CourseCalendar.find_by!(oauth_credential: credential)).to have_attributes(provider: "microsoft", external_calendar_id: "AAMkSyntheticCalendarNew")
    end

    it "keeps a calendar that still exists" do
      calendar
      stub_request(:get, "#{graph}/me/calendars/AAMkSyntheticCalendar1").with(query: hash_including({}))
        .to_return(graph_json_response("calendar_found"))

      expect(service.create_or_get_course_calendar).to eq("AAMkSyntheticCalendar1")
    end

    it "creates the calendar again when the person deleted it in Outlook" do
      create(:calendar_event, course_calendar: calendar, meeting_time: meeting_time)
      stub_request(:get, "#{graph}/me/calendars/AAMkSyntheticCalendar1").with(query: hash_including({}))
        .to_return(graph_json_response("error_not_found", status: 404))
      stub_request(:post, "#{graph}/me/calendars").to_return(graph_json_response("calendar_created"))

      expect(service.create_or_get_course_calendar).to eq("AAMkSyntheticCalendarNew")
      expect(calendar.reload.external_calendar_id).to eq("AAMkSyntheticCalendarNew")
      expect(calendar.calendar_events).to be_empty
    end

    it "tracks the primary calendar and creates nothing when the person asks for it" do
      credential
      stub_request(:get, "#{graph}/me/calendar").with(query: hash_including({})).to_return(graph_json_response("calendar_primary"))

      expect(service.create_or_get_course_calendar(placement: "primary")).to eq("AAMkSyntheticPrimaryCalendar")
      expect(CourseCalendar.find_by!(oauth_credential: credential)).to have_attributes(placement: "primary", external_calendar_id: "AAMkSyntheticPrimaryCalendar")
      expect(a_request(:post, "#{graph}/me/calendars")).not_to have_been_made
    end

    it "keeps the placement of a calendar that exists" do
      calendar
      stub_request(:get, "#{graph}/me/calendars/AAMkSyntheticCalendar1").with(query: hash_including({}))
        .to_return(graph_json_response("calendar_found"))

      expect(service.create_or_get_course_calendar(placement: "primary")).to eq("AAMkSyntheticCalendar1")
      expect(calendar.reload).to be_separate_placement
    end

    it "needs a Microsoft credential" do
      expect { service.create_or_get_course_calendar }.to raise_error(MicrosoftGraph::AuthError)
    end
  end

  describe "#update_calendar_events" do
    it "does nothing without a Microsoft calendar" do
      credential

      expect(service.update_calendar_events([ class_event ])).to eq(created: 0, updated: 0, skipped: 0)
    end

    it "creates a new event and stores both Graph ids" do
      calendar
      create_stub = stub_event_create

      stats = service.update_calendar_events([ class_event ])

      expect(stats).to eq(created: 1, updated: 0, skipped: 0)
      expect(create_stub).to have_been_requested.once
      expect(a_request(:post, "#{graph}/me/calendars/AAMkSyntheticCalendar1/events").with(body: hash_including("showAs" => "busy"))).to have_been_made
      expect(calendar.calendar_events.sole).to have_attributes(
        meeting_time_id: meeting_time.id, external_event_id: created_event_id, external_ical_uid: created_ical_uid
      )
    end

    it "cancels the occurrences an EXDATE removes" do
      calendar
      stub_event_create
      instances = stub_request(:get, "#{graph}/me/events/#{created_event_id}/instances")
                  .with(query: hash_including("startDateTime" => "2026-10-12T00:00:00-04:00"))
                  .to_return(graph_json_response("event_instances"))
      cancel = stub_request(:delete, "#{graph}/me/events/AAMkSyntheticOccurrence1").to_return(status: 204)

      service.update_calendar_events([ class_event.merge(
        recurrence: [ "RRULE:FREQ=WEEKLY;UNTIL=20261212T045959Z;BYDAY=MO", "EXDATE;TZID=America/New_York:20261012T090000" ]
      ) ])

      expect(instances).to have_been_requested
      expect(cancel).to have_been_requested
    end

    it "skips an event that has not changed" do
      calendar
      create_stub = stub_event_create
      service.update_calendar_events([ class_event ])

      stats = described_class.new(user).update_calendar_events([ class_event ])

      expect(stats).to eq(created: 0, updated: 0, skipped: 1)
      expect(create_stub).to have_been_requested.once
    end

    it "updates a tracked event when forced" do
      row = create(:calendar_event, :microsoft, course_calendar: calendar, meeting_time: meeting_time,
                                                external_event_id: created_event_id)
      # The preference templates rewrite the subject, so match on the time.
      patch = stub_request(:patch, "#{graph}/me/events/#{created_event_id}")
              .with(body: hash_including("start" => { "dateTime" => "2026-09-14T09:00:00", "timeZone" => "Eastern Standard Time" }))
              .to_return(graph_json_response("event_updated"))

      stats = service.update_calendar_events([ class_event ], force: true)

      expect(stats).to eq(created: 0, updated: 1, skipped: 0)
      expect(patch).to have_been_requested
      expect(row.reload.event_data_hash).to be_present
    end

    it "follows an event that moved folders by its iCalUId" do
      row = create(:calendar_event, course_calendar: calendar, meeting_time: meeting_time,
                                    external_event_id: "AAMkSyntheticEventOld", external_ical_uid: created_ical_uid)
      stub_request(:patch, "#{graph}/me/events/AAMkSyntheticEventOld").to_return(graph_json_response("error_not_found", status: 404))
      lookup = stub_request(:get, "#{graph}/me/events")
               .with(query: hash_including("$filter" => "iCalUId eq '#{created_ical_uid}'"))
               .to_return(graph_json_response("events_by_ical_uid"))
      moved = stub_request(:patch, "#{graph}/me/events/AAMkSyntheticEventMoved").to_return(graph_json_response("event_updated"))

      service.update_calendar_events([ class_event ], force: true)

      expect(lookup).to have_been_requested
      expect(moved).to have_been_requested
      expect(row.reload.external_event_id).to eq("AAMkSyntheticEventMoved")
    end

    it "creates the event again when neither id finds it" do
      old_row = create(:calendar_event, course_calendar: calendar, meeting_time: meeting_time,
                                        external_event_id: "AAMkSyntheticEventGone", external_ical_uid: "synthetic-gone-uid")
      stub_request(:patch, "#{graph}/me/events/AAMkSyntheticEventGone").to_return(graph_json_response("error_not_found", status: 404))
      stub_request(:get, "#{graph}/me/events").with(query: hash_including({})).to_return(graph_json_response("events_empty"))
      create_stub = stub_event_create

      expect { service.update_calendar_events([ class_event ], force: true) }.not_to have_enqueued_job(MicrosoftGraphEventDeleteJob)

      expect(create_stub).to have_been_requested
      expect(CalendarEvent.exists?(old_row.id)).to be(false)
      expect(calendar.calendar_events.sole.external_event_id).to eq(created_event_id)
    end

    it "deletes a future event the schedule no longer has" do
      other_meeting_time = create(:course_meeting_time)
      row = create(:calendar_event, course_calendar: calendar, meeting_time: other_meeting_time,
                                    external_event_id: "AAMkSyntheticEventDropped", end_time: zone.local(2026, 12, 1, 10))
      delete = stub_request(:delete, "#{graph}/me/events/AAMkSyntheticEventDropped").to_return(status: 204)

      expect { service.update_calendar_events([]) }.not_to have_enqueued_job(MicrosoftGraphEventDeleteJob)

      expect(delete).to have_been_requested
      expect(CalendarEvent.exists?(row.id)).to be(false)
    end

    it "keeps a past event the schedule no longer has" do
      other_meeting_time = create(:course_meeting_time)
      row = create(:calendar_event, course_calendar: calendar, meeting_time: other_meeting_time,
                                    external_event_id: "AAMkSyntheticEventPast", end_time: zone.local(2026, 5, 1, 10))

      service.update_calendar_events([])

      expect(CalendarEvent.exists?(row.id)).to be(true)
    end
  end

  describe "keeping edits made in Outlook" do
    let!(:row) do
      create(:calendar_event, course_calendar: calendar, meeting_time: meeting_time,
                              external_event_id: created_event_id, external_ical_uid: created_ical_uid,
                              summary: "Synthetic Course", location: "Synthetic Hall - 101",
                              start_time: zone.local(2026, 9, 14, 8, 0), end_time: zone.local(2026, 9, 14, 9, 15),
                              event_data_hash: "stale")
    end

    def stub_event_fetch(event_id = created_event_id, **overrides)
      body = JSON.parse(graph_fixture("event_fetched")).merge(overrides.deep_stringify_keys)
      stub_request(:get, "#{graph}/me/events/#{event_id}")
        .with(query: hash_including("$select" => MicrosoftGraph::EventEdits::SELECT))
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
    end

    def outlook_time(hour, minute = 0)
      { "dateTime" => format("2026-09-14T%02d:%02d:00.0000000", hour, minute), "timeZone" => "Eastern Standard Time" }
    end

    it "sends the app's new time when the person changed nothing" do
      stub_event_fetch(start: outlook_time(8), end: outlook_time(9, 15))
      patch = stub_request(:patch, "#{graph}/me/events/#{created_event_id}")
              .with(body: hash_including("start" => outlook_time(9).merge("dateTime" => "2026-09-14T09:00:00")))
              .to_return(graph_json_response("event_updated"))

      stats = service.update_calendar_events([ class_event ])

      expect(stats).to eq(created: 0, updated: 1, skipped: 0)
      expect(patch).to have_been_requested
      expect(row.reload).to have_attributes(user_edited_fields: nil, start_time: zone.local(2026, 9, 14, 9, 0))
    end

    it "sends no showAs after it reads the event, so the person's free or busy choice stays" do
      stub_event_fetch(start: outlook_time(8), end: outlook_time(9, 15))
      sent  = nil
      patch = stub_request(:patch, "#{graph}/me/events/#{created_event_id}")
              .with { |request| sent = JSON.parse(request.body) }
              .to_return(graph_json_response("event_updated"))

      service.update_calendar_events([ class_event ])

      expect(patch).to have_been_requested
      expect(sent).not_to have_key("showAs")
    end

    it "keeps a title and a time the person changed" do
      stub_event_fetch(subject: "Renamed in Outlook", start: outlook_time(11), end: outlook_time(9, 15))
      patch = stub_request(:patch, "#{graph}/me/events/#{created_event_id}")
              .with(body: hash_including("subject" => "Renamed in Outlook",
                                         "start"   => { "dateTime" => "2026-09-14T11:00:00", "timeZone" => "Eastern Standard Time" },
                                         "end"     => { "dateTime" => "2026-09-14T10:15:00", "timeZone" => "Eastern Standard Time" }))
              .to_return(graph_json_response("event_updated"))

      service.update_calendar_events([ class_event ])

      expect(patch).to have_been_requested
      expect(row.reload.user_edited_fields).to contain_exactly("summary", "start_time")
      expect(row.summary).to eq("Renamed in Outlook")
    end

    it "keeps a field the person changed in an earlier sync" do
      row.update!(user_edited_fields: [ "location" ], location: "Room chosen in Outlook")
      stub_event_fetch(start: outlook_time(8), end: outlook_time(9, 15), location: { displayName: "Room chosen in Outlook" })
      patch = stub_request(:patch, "#{graph}/me/events/#{created_event_id}")
              .with(body: hash_including("location" => { "displayName" => "Room chosen in Outlook" }))
              .to_return(graph_json_response("event_updated"))

      service.update_calendar_events([ class_event ])

      expect(patch).to have_been_requested
      expect(row.reload.user_edited_fields).to eq([ "location" ])
    end

    it "leaves an event alone when the person changed its recurrence" do
      row.update!(recurrence: [ "RRULE:FREQ=WEEKLY;UNTIL=20261212T045959Z;BYDAY=MO" ])
      stub_event_fetch(start: outlook_time(8), end: outlook_time(9, 15), recurrence: {
                         pattern: { type: "weekly", interval: 1, daysOfWeek: %w[monday wednesday], firstDayOfWeek: "sunday" },
                         range:   { type: "endDate", startDate: "2026-09-14", endDate: "2026-12-11" }
                       })

      stats = service.update_calendar_events([ class_event ])

      expect(stats).to eq(created: 0, updated: 0, skipped: 1)
      expect(a_request(:patch, "#{graph}/me/events/#{created_event_id}")).not_to have_been_made
      expect(row.reload.last_synced_at).to be_present
    end

    it "does not count an unchanged series as a recurrence edit" do
      rule = [ "RRULE:FREQ=WEEKLY;UNTIL=20261212T045959Z;BYDAY=MO" ]
      row.update!(recurrence: rule)
      stub_event_fetch(start: outlook_time(8), end: outlook_time(9, 15), recurrence: {
                         pattern: { type: "weekly", interval: 1, month: 0, dayOfMonth: 0, daysOfWeek: %w[monday], firstDayOfWeek: "sunday", index: "first" },
                         range:   { type: "endDate", startDate: "2026-09-14", endDate: "2026-12-11", recurrenceTimeZone: "Eastern Standard Time", numberOfOccurrences: 0 }
                       })
      patch = stub_request(:patch, "#{graph}/me/events/#{created_event_id}").to_return(graph_json_response("event_updated"))

      service.update_calendar_events([ class_event.merge(recurrence: rule) ])

      expect(patch).to have_been_requested
    end

    it "reads a moved event by its iCalUId before it updates it" do
      stub_request(:get, "#{graph}/me/events/#{created_event_id}").with(query: hash_including({}))
        .to_return(graph_json_response("error_not_found", status: 404))
      stub_request(:get, "#{graph}/me/events")
        .with(query: hash_including("$filter" => "iCalUId eq '#{created_ical_uid}'"))
        .to_return(graph_json_response("events_by_ical_uid"))
      stub_event_fetch("AAMkSyntheticEventMoved", start: outlook_time(8), end: outlook_time(9, 15))
      moved = stub_request(:patch, "#{graph}/me/events/AAMkSyntheticEventMoved").to_return(graph_json_response("event_updated"))

      service.update_calendar_events([ class_event ])

      expect(moved).to have_been_requested
      expect(row.reload.external_event_id).to eq("AAMkSyntheticEventMoved")
    end

    it "writes the app's values and forgets the edits when forced" do
      row.update!(user_edited_fields: [ "summary" ])
      patch = stub_request(:patch, "#{graph}/me/events/#{created_event_id}").to_return(graph_json_response("event_updated"))

      service.update_calendar_events([ class_event ], force: true)

      expect(patch).to have_been_requested
      expect(a_request(:get, "#{graph}/me/events/#{created_event_id}")).not_to have_been_made
      expect(row.reload.user_edited_fields).to be_nil
    end
  end

  describe "event colors" do
    let(:categories_url) { "#{graph}/me/outlook/masterCategories" }

    before { user.user_extension_config.update!(default_color_lecture: GoogleColors::BANANA) }

    it "creates the category for a lecture color once and sets it on each new event" do
      calendar
      create_stub = stub_request(:post, "#{graph}/me/calendars/AAMkSyntheticCalendar1/events")
                    .with(body: hash_including("categories" => [ "WIT Banana" ]))
                    .to_return(graph_json_response("event_created"))
      second_event = class_event.merge(meeting_time_id: create(:course_meeting_time).id)

      service.update_calendar_events([ class_event, second_event ])

      expect(create_stub).to have_been_requested.twice
      expect(master_categories).to have_been_requested.once
      expect(a_request(:post, categories_url).with(body: { displayName: "WIT Banana", color: "preset3" }.to_json)).to have_been_made.once
    end

    it "keeps the person's own categories and swaps the old WIT category on update" do
      create(:calendar_event, course_calendar: calendar, meeting_time: meeting_time,
                              external_event_id: created_event_id, summary: "Synthetic Course", location: "Synthetic Hall - 101",
                              start_time: zone.local(2026, 9, 14, 9, 0), end_time: zone.local(2026, 9, 14, 10, 15),
                              event_data_hash: "stale")
      body = JSON.parse(graph_fixture("event_fetched")).merge("categories" => [ "Synthetic Personal", "WIT Tomato" ])
      stub_request(:get, "#{graph}/me/events/#{created_event_id}").with(query: hash_including({}))
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
      patch = stub_request(:patch, "#{graph}/me/events/#{created_event_id}")
              .with(body: hash_including("categories" => [ "Synthetic Personal", "WIT Banana" ]))
              .to_return(graph_json_response("event_updated"))

      service.update_calendar_events([ class_event ])

      expect(patch).to have_been_requested
    end
  end

  describe "#update_specific_events" do
    it "creates only the events it is given" do
      calendar
      stub_event_create

      expect(service.update_specific_events([ class_event ])).to eq(created: 1, updated: 0, skipped: 0)
    end
  end

  describe "#delete_events" do
    it "deletes each remote event and its row" do
      row = create(:calendar_event, course_calendar: calendar, meeting_time: meeting_time, external_event_id: created_event_id)
      delete = stub_request(:delete, "#{graph}/me/events/#{created_event_id}").to_return(status: 204)

      expect(service.delete_events([ row ])).to eq(1)
      expect(delete).to have_been_requested
      expect(CalendarEvent.exists?(row.id)).to be(false)
    end
  end

  describe "#delete_calendar_event" do
    it "deletes a moved event by its iCalUId when the stored id is gone" do
      credential
      stub_request(:delete, "#{graph}/me/events/AAMkSyntheticEventOld").to_return(graph_json_response("error_not_found", status: 404))
      stub_request(:get, "#{graph}/me/events").with(query: hash_including({})).to_return(graph_json_response("events_by_ical_uid"))
      moved = stub_request(:delete, "#{graph}/me/events/AAMkSyntheticEventMoved").to_return(status: 204)

      service.delete_calendar_event("AAMkSyntheticEventOld", created_ical_uid)

      expect(moved).to have_been_requested
    end

    it "treats an event that is gone everywhere as deleted" do
      credential
      stub_request(:delete, "#{graph}/me/events/AAMkSyntheticEventOld").to_return(graph_json_response("error_not_found", status: 404))

      expect { service.delete_calendar_event("AAMkSyntheticEventOld") }.not_to raise_error
    end
  end

  describe "#change_placement" do
    let(:primary_calendar) do
      create(:course_calendar, :primary, oauth_credential: credential, external_calendar_id: "AAMkSyntheticPrimaryCalendar")
    end

    it "moves to the primary calendar: reads its id first, then deletes the separate calendar and its rows" do
      create(:calendar_event, course_calendar: calendar, meeting_time: meeting_time)
      order = []
      stub_request(:get, "#{graph}/me/calendar").with(query: hash_including({})).to_return do
        order << :read_primary
        graph_json_response("calendar_primary")
      end
      stub_request(:delete, "#{graph}/me/calendars/AAMkSyntheticCalendar1").to_return do
        order << :delete_separate
        { status: 204 }
      end

      expect(service.change_placement("primary")).to eq("AAMkSyntheticPrimaryCalendar")

      expect(order).to eq(%i[read_primary delete_separate])
      expect(calendar.reload).to have_attributes(placement: "primary", external_calendar_id: "AAMkSyntheticPrimaryCalendar", last_synced_at: nil)
      expect(calendar.calendar_events).to be_empty
    end

    it "keeps the separate calendar when the primary calendar cannot be read" do
      calendar
      stub_request(:get, "#{graph}/me/calendar").with(query: hash_including({})).to_return(graph_json_response("error_forbidden", status: 403))

      expect { service.change_placement("primary") }.to raise_error(MicrosoftGraph::Error)

      expect(calendar.reload).to be_separate_placement
      expect(a_request(:delete, "#{graph}/me/calendars/AAMkSyntheticCalendar1")).not_to have_been_made
    end

    it "moves to a separate calendar: deletes each tracked event, never the primary calendar" do
      row = create(:calendar_event, course_calendar: primary_calendar, meeting_time: meeting_time, external_event_id: "AAMkSyntheticEvent1")
      delete_event = stub_request(:delete, "#{graph}/me/events/AAMkSyntheticEvent1").to_return(status: 204)
      stub_request(:post, "#{graph}/me/calendars").to_return(graph_json_response("calendar_created"))

      expect(service.change_placement("separate")).to eq("AAMkSyntheticCalendarNew")

      expect(delete_event).to have_been_requested
      expect(a_request(:delete, %r{/me/calendars/})).not_to have_been_made
      expect(CalendarEvent.exists?(row.id)).to be(false)
      expect(primary_calendar.reload).to have_attributes(placement: "separate", external_calendar_id: "AAMkSyntheticCalendarNew")
    end

    it "stops the move while an event delete has failed, so the sync never updates the old event" do
      create(:calendar_event, course_calendar: primary_calendar, meeting_time: meeting_time, external_event_id: "AAMkSyntheticEventFails")
      stub_request(:delete, "#{graph}/me/events/AAMkSyntheticEventFails").to_return(status: 500, body: "{}")

      expect { service.change_placement("separate") }.to raise_error(MicrosoftGraph::Error)

      expect(primary_calendar.reload).to be_primary_placement
      expect(a_request(:post, "#{graph}/me/calendars")).not_to have_been_made
    end

    it "does nothing when the placement is already the one asked for" do
      calendar

      expect(service.change_placement("separate")).to eq("AAMkSyntheticCalendar1")
      expect(a_request(:any, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it "refuses a placement it does not know" do
      calendar

      expect { service.change_placement("shared") }.to raise_error(ArgumentError)
    end
  end

  describe "#remove_course_events" do
    it "deletes only the tracked events of a primary calendar, and carries on after a failure" do
      primary = create(:course_calendar, :primary, oauth_credential: credential, external_calendar_id: "AAMkSyntheticPrimaryCalendar")
      failed  = create(:calendar_event, course_calendar: primary, external_event_id: "AAMkSyntheticEventFails")
      removed = create(:calendar_event, course_calendar: primary, external_event_id: "AAMkSyntheticEvent1")
      stub_request(:delete, "#{graph}/me/events/AAMkSyntheticEventFails").to_return(status: 500, body: "{}")
      stub_request(:delete, "#{graph}/me/events/AAMkSyntheticEvent1").to_return(status: 204)

      expect { service.remove_course_events(primary) }.not_to raise_error

      expect(CalendarEvent.exists?(removed.id)).to be(false)
      expect(CalendarEvent.exists?(failed.id)).to be(true)
      expect(a_request(:delete, %r{/me/calendars/})).not_to have_been_made
    end

    it "deletes the whole calendar when it is the app's own" do
      delete = stub_request(:delete, "#{graph}/me/calendars/AAMkSyntheticCalendar1").to_return(status: 204)

      service.remove_course_events(calendar)

      expect(delete).to have_been_requested
    end
  end

  describe "#delete_calendar" do
    it "refuses to delete a calendar that is tracked as a primary calendar" do
      create(:course_calendar, :primary, oauth_credential: credential, external_calendar_id: "AAMkSyntheticPrimaryCalendar")

      service.delete_calendar("AAMkSyntheticPrimaryCalendar")

      expect(a_request(:any, /graph\.microsoft\.com/)).not_to have_been_made
    end

    it "treats a missing calendar as deleted" do
      credential
      stub_request(:delete, "#{graph}/me/calendars/AAMkSyntheticCalendar1").to_return(graph_json_response("error_not_found", status: 404))

      expect { service.delete_calendar("AAMkSyntheticCalendar1") }.not_to raise_error
    end
  end
end
