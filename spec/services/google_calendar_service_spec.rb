# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendarService do
  let(:user) { create(:user) }
  let(:oauth_credential) { create(:oauth_credential, user: user) }
  let(:google_calendar) { create(:google_calendar, oauth_credential: oauth_credential) }
  let(:service) { described_class.new(user) }

  describe "#normalize_color_id" do
    it "returns numeric ID when given an integer" do
      expect(service.send(:normalize_color_id, 5)).to eq(5)
    end

    it "returns numeric ID when given a numeric string" do
      expect(service.send(:normalize_color_id, "11")).to eq(11)
    end

    it "returns nil for invalid numeric IDs" do
      expect(service.send(:normalize_color_id, 0)).to be_nil
      expect(service.send(:normalize_color_id, 12)).to be_nil
    end

    it "converts hex codes to numeric IDs" do
      expect(service.send(:normalize_color_id, "#fbd75b")).to eq(5)  # EVENT_BANANA
      expect(service.send(:normalize_color_id, "#dc2127")).to eq(11) # EVENT_TOMATO
      expect(service.send(:normalize_color_id, "#e1e1e1")).to eq(8)  # EVENT_GRAPHITE
    end

    it "handles uppercase hex codes" do
      expect(service.send(:normalize_color_id, "#FBD75B")).to eq(5)
    end

    it "converts WITCC hex codes to numeric IDs" do
      expect(service.send(:normalize_color_id, "#039be5")).to eq(7)  # WITCC_PEACOCK -> EVENT_PEACOCK
      expect(service.send(:normalize_color_id, "#f6bf26")).to eq(5)  # WITCC_BANANA -> EVENT_BANANA
      expect(service.send(:normalize_color_id, "#d50000")).to eq(11) # WITCC_TOMATO -> EVENT_TOMATO
      expect(service.send(:normalize_color_id, "#0b8043")).to eq(10) # WITCC_BASIL -> EVENT_BASIL
    end

    it "handles uppercase WITCC hex codes" do
      expect(service.send(:normalize_color_id, "#039BE5")).to eq(7) # WITCC_PEACOCK
      expect(service.send(:normalize_color_id, "#F6BF26")).to eq(5) # WITCC_BANANA
    end

    it "returns nil for unknown hex codes" do
      expect(service.send(:normalize_color_id, "#000000")).to be_nil
    end

    it "returns nil for blank values" do
      expect(service.send(:normalize_color_id, nil)).to be_nil
      expect(service.send(:normalize_color_id, "")).to be_nil
    end
  end

  describe "#update_db_from_gcal_event" do
    let(:db_event) do
      create(:google_calendar_event, :with_meeting_time,
             google_calendar: google_calendar,
             google_event_id: "test_event_123",
             summary: "Original Course Title",
             location: "Room 101",
             start_time: Time.zone.parse("2025-01-15 09:00:00"),
             end_time: Time.zone.parse("2025-01-15 10:30:00"),
             recurrence: ["RRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20250515T235959Z"])
    end

    let(:gcal_event) do
      double("Google::Apis::CalendarV3::Event",
             summary: "User Modified Title",
             location: "Room 202 - User Changed",
             start: double(date_time: "2025-01-15T10:00:00-05:00", date: nil),
             end: double(date_time: "2025-01-15T11:30:00-05:00", date: nil),
             recurrence: ["RRULE:FREQ=WEEKLY;BYDAY=TU;UNTIL=20250515T235959Z"])
    end

    it "updates the database with Google Calendar event data" do
      service.send(:update_db_from_gcal_event, db_event, gcal_event)

      db_event.reload
      expect(db_event.summary).to eq("User Modified Title")
      expect(db_event.location).to eq("Room 202 - User Changed")
      expect(db_event.start_time.to_i).to eq(Time.zone.parse("2025-01-15 10:00:00").to_i)
      expect(db_event.end_time.to_i).to eq(Time.zone.parse("2025-01-15 11:30:00").to_i)
      expect(db_event.recurrence).to eq(["RRULE:FREQ=WEEKLY;BYDAY=TU;UNTIL=20250515T235959Z"])
    end

    it "updates the event_data_hash" do
      original_hash = db_event.event_data_hash

      service.send(:update_db_from_gcal_event, db_event, gcal_event)

      db_event.reload
      expect(db_event.event_data_hash).not_to eq(original_hash)
      expect(db_event.event_data_hash).to be_present
    end

    it "updates the last_synced_at timestamp" do
      service.send(:update_db_from_gcal_event, db_event, gcal_event)

      db_event.reload
      expect(db_event.last_synced_at).to be_within(1.second).of(Time.current)
    end
  end

  describe "#parse_gcal_time" do
    context "with date_time" do
      let(:time_obj) { double(date_time: "2025-01-15T09:00:00-05:00", date: nil) }

      it "parses the datetime to Eastern timezone" do
        result = service.send(:parse_gcal_time, time_obj)
        expect(result).to be_a(Time)
        # Eastern Time can be either EST or EDT depending on daylight saving time
        expect(result.zone).to match(/^E[SD]T$/)
        expect(result.hour).to eq(9)
      end
    end

    context "with date only (all-day event)" do
      let(:time_obj) { double(date_time: nil, date: "2025-01-15") }

      it "parses the date to Eastern timezone" do
        result = service.send(:parse_gcal_time, time_obj)
        expect(result).to be_a(Time)
        expect(result.to_date).to eq(Date.parse("2025-01-15"))
      end
    end

    context "with nil time_obj" do
      it "returns nil" do
        expect(service.send(:parse_gcal_time, nil)).to be_nil
      end
    end
  end

  describe "#normalize_recurrence" do
    context "with nil recurrence" do
      it "returns nil" do
        expect(service.send(:normalize_recurrence, nil)).to be_nil
      end
    end

    context "with empty array" do
      it "returns nil" do
        expect(service.send(:normalize_recurrence, [])).to be_nil
      end
    end

    context "with single recurrence rule" do
      it "returns sorted array" do
        recurrence = ["RRULE:FREQ=WEEKLY;BYDAY=MO"]
        expect(service.send(:normalize_recurrence, recurrence)).to eq(["RRULE:FREQ=WEEKLY;BYDAY=MO"])
      end
    end

    context "with multiple recurrence rules" do
      it "returns sorted array" do
        recurrence = ["RRULE:FREQ=WEEKLY;BYDAY=WE", "RRULE:FREQ=WEEKLY;BYDAY=MO"]
        result = service.send(:normalize_recurrence, recurrence)
        expect(result).to eq(["RRULE:FREQ=WEEKLY;BYDAY=MO", "RRULE:FREQ=WEEKLY;BYDAY=WE"])
      end
    end
  end

  describe "#update_event_in_calendar integration" do
    let(:meeting_time) { create(:meeting_time) }
    let(:db_event) do
      create(:google_calendar_event,
             google_calendar: google_calendar,
             google_event_id: "test_event_123",
             meeting_time: meeting_time,
             summary: "Original Course Title",
             location: "Room 101",
             start_time: Time.zone.parse("2025-01-15 09:00:00"),
             end_time: Time.zone.parse("2025-01-15 10:30:00"),
             recurrence: ["RRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20250515T235959Z"],
             event_data_hash: GoogleCalendarEvent.generate_data_hash({
                                                                       summary: "Original Course Title",
                                                                       location: "Room 101",
                                                                       start_time: Time.zone.parse("2025-01-15 09:00:00"),
                                                                       end_time: Time.zone.parse("2025-01-15 10:30:00"),
                                                                       recurrence: ["RRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20250515T235959Z"]
                                                                     }))
    end

    let(:course_event) do
      {
        summary: "Updated Course Title from System",
        location: "Room 303",
        start_time: Time.zone.parse("2025-01-15 09:00:00"),
        end_time: Time.zone.parse("2025-01-15 10:30:00"),
        recurrence: ["RRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20250515T235959Z"],
        meeting_time_id: meeting_time.id
      }
    end

    let(:mock_service) { double("Google::Apis::CalendarV3::CalendarService") }

    context "when user has edited specific fields in Google Calendar" do
      let(:gcal_event) do
        double("Google::Apis::CalendarV3::Event",
               summary: "User Modified Title in GCal",
               location: "Room 999 - User Changed",
               description: nil,
               start: double(date_time: "2025-01-15T09:00:00-05:00", date: nil),
               end: double(date_time: "2025-01-15T10:30:00-05:00", date: nil),
               recurrence: ["RRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20250515T235959Z"])
      end

      let(:updated_gcal_event) do
        double("Google::Apis::CalendarV3::Event", id: db_event.google_event_id)
      end

      before do
        allow(mock_service).to receive(:get_event).with(
          google_calendar.google_calendar_id,
          db_event.google_event_id
        ).and_return(gcal_event)
        allow(mock_service).to receive(:update_event).and_return(updated_gcal_event)
        # Stub apply_preferences_to_event to return course_event as-is
        allow(service).to receive_messages(service_account_calendar_service: mock_service, apply_preferences_to_event: course_event)
      end

      it "preserves user-edited fields while allowing system updates to other fields" do
        service.send(:update_event_in_calendar, mock_service, google_calendar, db_event, course_event)

        db_event.reload
        # User-edited fields should be preserved
        expect(db_event.summary).to eq("User Modified Title in GCal")
        expect(db_event.location).to eq("Room 999 - User Changed")
        # Google Calendar should be updated with merged data
        expect(mock_service).to have_received(:update_event)
      end

      it "marks the event as synced" do
        service.send(:update_event_in_calendar, mock_service, google_calendar, db_event, course_event)

        db_event.reload
        expect(db_event.last_synced_at).to be_within(1.second).of(Time.current)
      end

      it "tracks which fields were user-edited" do
        service.send(:update_event_in_calendar, mock_service, google_calendar, db_event, course_event)

        db_event.reload
        expect(db_event.user_edited_fields).to include("summary", "location")
      end
    end

    context "when event has previously tracked user-edited fields" do
      let(:gcal_event) do
        double("Google::Apis::CalendarV3::Event",
               summary: "User Modified Title in GCal",
               location: "Room 101", # Same as DB - not newly edited
               description: nil,
               start: double(date_time: "2025-01-15T09:00:00-05:00", date: nil),
               end: double(date_time: "2025-01-15T10:30:00-05:00", date: nil),
               recurrence: ["RRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20250515T235959Z"])
      end

      let(:updated_gcal_event) do
        double("Google::Apis::CalendarV3::Event", id: db_event.google_event_id)
      end

      before do
        # Previously tracked that user edited location
        db_event.update!(user_edited_fields: %w[location])
        allow(mock_service).to receive_messages(get_event: gcal_event, update_event: updated_gcal_event)
        allow(service).to receive_messages(service_account_calendar_service: mock_service, apply_preferences_to_event: course_event)
      end

      it "merges previously tracked fields with newly detected edits" do
        service.send(:update_event_in_calendar, mock_service, google_calendar, db_event, course_event)

        db_event.reload
        # Should track both previously tracked (location) and newly detected (summary)
        expect(db_event.user_edited_fields).to include("summary", "location")
      end

      it "preserves all user-edited field values" do
        service.send(:update_event_in_calendar, mock_service, google_calendar, db_event, course_event)

        db_event.reload
        # Summary was newly edited, location was previously tracked
        expect(db_event.summary).to eq("User Modified Title in GCal")
        # Location should remain the user-edited value from GCal, not system value
        expect(db_event.location).to eq("Room 101")
      end
    end

    context "when user has not edited the event" do
      let(:gcal_event) do
        double("Google::Apis::CalendarV3::Event",
               summary: "Original Course Title",
               location: "Room 101",
               description: nil,
               start: double(date_time: "2025-01-15T09:00:00-05:00", date: nil),
               end: double(date_time: "2025-01-15T10:30:00-05:00", date: nil),
               recurrence: ["RRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20250515T235959Z"])
      end

      let(:updated_gcal_event) do
        double("Google::Apis::CalendarV3::Event", id: db_event.google_event_id)
      end

      before do
        allow(mock_service).to receive(:get_event).with(
          google_calendar.google_calendar_id,
          db_event.google_event_id
        ).and_return(gcal_event)
        allow(mock_service).to receive(:update_event).and_return(updated_gcal_event)
        # Stub apply_preferences_to_event to return course_event as-is (bypass template rendering for this test)
        allow(service).to receive_messages(service_account_calendar_service: mock_service, apply_preferences_to_event: course_event)
      end

      it "updates Google Calendar with system changes" do
        service.send(:update_event_in_calendar, mock_service, google_calendar, db_event, course_event)

        expect(mock_service).to have_received(:update_event).with(
          google_calendar.google_calendar_id,
          db_event.google_event_id,
          an_instance_of(Google::Apis::CalendarV3::Event)
        )
      end

      it "updates the local database with system changes" do
        service.send(:update_event_in_calendar, mock_service, google_calendar, db_event, course_event)

        db_event.reload
        expect(db_event.summary).to eq("Updated Course Title from System")
        expect(db_event.location).to eq("Room 303")
      end
    end

    context "when event does not exist in Google Calendar" do
      before do
        allow(service).to receive(:service_account_calendar_service).and_return(mock_service)
        allow(mock_service).to receive(:get_event).and_raise(
          Google::Apis::ClientError.new("Not Found", status_code: 404)
        )
        allow(service).to receive(:create_event_in_calendar)
      end

      it "recreates the event" do
        service.send(:update_event_in_calendar, mock_service, google_calendar, db_event, course_event)

        expect(service).to have_received(:create_event_in_calendar).with(
          mock_service,
          google_calendar,
          course_event
        )
      end

      it "destroys the old database record" do
        service.send(:update_event_in_calendar, mock_service, google_calendar, db_event, course_event)

        expect(GoogleCalendarEvent.exists?(db_event.id)).to be false
      end
    end

    context "when force=true is passed" do
      let(:gcal_event) do
        double("Google::Apis::CalendarV3::Event",
               summary: "User Modified Title in GCal",
               location: "Room 999 - User Changed",
               start: double(date_time: "2025-01-15T09:00:00-05:00", date: nil),
               end: double(date_time: "2025-01-15T10:30:00-05:00", date: nil),
               recurrence: ["RRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20250515T235959Z"])
      end

      let(:updated_gcal_event) do
        double("Google::Apis::CalendarV3::Event", id: db_event.google_event_id)
      end

      before do
        # Stub get_event so we can verify it's not called when force=true
        allow(mock_service).to receive(:get_event)
        allow(mock_service).to receive(:update_event).and_return(updated_gcal_event)
        # Stub apply_preferences_to_event to return course_event as-is (bypass template rendering for this test)
        allow(service).to receive_messages(service_account_calendar_service: mock_service, apply_preferences_to_event: course_event)
      end

      it "skips user edit detection and updates the event" do
        service.send(:update_event_in_calendar, mock_service, google_calendar, db_event, course_event, force: true)

        expect(mock_service).not_to have_received(:get_event)
        expect(mock_service).to have_received(:update_event).with(
          google_calendar.google_calendar_id,
          db_event.google_event_id,
          an_instance_of(Google::Apis::CalendarV3::Event)
        )
      end

      it "applies system changes even if user previously edited the event" do
        service.send(:update_event_in_calendar, mock_service, google_calendar, db_event, course_event, force: true)

        db_event.reload
        expect(db_event.summary).to eq("Updated Course Title from System")
        expect(db_event.location).to eq("Room 303")
      end

      it "clears the user_edited_fields after successful update" do
        db_event.update!(user_edited_fields: %w[summary location])

        service.send(:update_event_in_calendar, mock_service, google_calendar, db_event, course_event, force: true)

        db_event.reload
        expect(db_event.user_edited_fields).to be_nil
      end

      it "overwrites previously tracked user edits when force=true" do
        db_event.update!(user_edited_fields: %w[summary location])

        result = service.send(:update_event_in_calendar, mock_service, google_calendar, db_event, course_event, force: true)

        expect(result).to eq(:updated)
        expect(mock_service).to have_received(:update_event)
        db_event.reload
        expect(db_event.summary).to eq("Updated Course Title from System")
      end

      context "with color preferences" do
        before do
          # Don't stub apply_preferences_to_event for this test - we need it to apply the color preference
          allow(service).to receive(:apply_preferences_to_event).and_call_original
        end

        it "applies color preferences when force=true" do
          # Create a calendar preference with a custom color
          create(:calendar_preference, user: user, color_id: 11)

          service.send(:update_event_in_calendar, mock_service, google_calendar, db_event, course_event, force: true)

          expect(mock_service).to have_received(:update_event) do |_calendar_id, _event_id, event|
            expect(event.color_id).to eq("11")
          end
        end
      end
    end
  end

  describe "#add_calendar_to_user_list_for_email" do
    let(:calendar_id) { "test_calendar_id@group.calendar.google.com" }
    let(:email) { "test@example.com" }
    let(:credential) { create(:oauth_credential, user: user, email: email) }
    let(:mock_service) { double("Google::Apis::CalendarV3::CalendarService") }
    let(:calendar_list_entry) { instance_double(Google::Apis::CalendarV3::CalendarListEntry) }

    before do
      allow(user).to receive(:google_credential_for_email).with(email).and_return(credential)
      allow(service).to receive(:user_calendar_service_for_credential).with(credential).and_return(mock_service)
      allow(Google::Apis::CalendarV3::CalendarListEntry).to receive(:new).and_return(calendar_list_entry)
    end

    context "when calendar is successfully added" do
      before do
        allow(mock_service).to receive(:insert_calendar_list).with(calendar_list_entry)
      end

      it "adds the calendar to the user's list" do
        service.send(:add_calendar_to_user_list_for_email, calendar_id, email)

        expect(mock_service).to have_received(:insert_calendar_list).with(calendar_list_entry)
      end
    end

    context "when calendar is already in list (409 error)" do
      before do
        allow(mock_service).to receive(:insert_calendar_list).and_raise(
          Google::Apis::ClientError.new("Conflict", status_code: 409)
        )
      end

      it "handles the error gracefully without raising" do
        expect do
          service.send(:add_calendar_to_user_list_for_email, calendar_id, email)
        end.not_to raise_error
      end

      it "logs a debug message" do
        allow(Rails.logger).to receive(:debug).and_call_original

        service.send(:add_calendar_to_user_list_for_email, calendar_id, email)

        # Debug logging uses a block, so we can't check the exact message easily
        # Just verify debug was called
        expect(Rails.logger).to have_received(:debug)
      end
    end

    context "when ACL has not propagated yet (404 error with retry)" do
      before do
        # First attempt fails with 404, second attempt succeeds
        call_count = 0
        allow(mock_service).to receive(:insert_calendar_list) do
          call_count += 1
          if call_count == 1
            raise Google::Apis::ClientError.new("Not Found", status_code: 404)
          end
          # Second call succeeds
        end
        allow(service).to receive(:sleep) # Don't actually sleep in tests
      end

      it "retries and succeeds" do
        expect do
          service.send(:add_calendar_to_user_list_for_email, calendar_id, email)
        end.not_to raise_error

        expect(mock_service).to have_received(:insert_calendar_list).twice
      end

      it "sleeps before retrying" do
        service.send(:add_calendar_to_user_list_for_email, calendar_id, email)

        expect(service).to have_received(:sleep).with(10)
      end

      it "logs a warning with retry information" do
        allow(Rails.logger).to receive(:warn)

        service.send(:add_calendar_to_user_list_for_email, calendar_id, email)

        expect(Rails.logger).to have_received(:warn).with(/not accessible yet.*retrying in 10s/)
      end
    end

    context "when ACL never propagates (404 error exhausts retries)" do
      before do
        allow(mock_service).to receive(:insert_calendar_list).and_raise(
          Google::Apis::ClientError.new("Not Found", status_code: 404)
        )
        allow(service).to receive(:sleep) # Don't actually sleep in tests
      end

      it "raises an error after max retries" do
        expect do
          service.send(:add_calendar_to_user_list_for_email, calendar_id, email)
        end.to raise_error(Google::Apis::ClientError)
      end

      it "retries the maximum number of times" do
        begin
          service.send(:add_calendar_to_user_list_for_email, calendar_id, email)
        rescue Google::Apis::ClientError
          # Expected
        end

        # Initial attempt + 3 retries = 4 total calls
        expect(mock_service).to have_received(:insert_calendar_list).exactly(4).times
      end

      it "logs an error after exhausting retries" do
        allow(Rails.logger).to receive(:error)

        begin
          service.send(:add_calendar_to_user_list_for_email, calendar_id, email)
        rescue Google::Apis::ClientError
          # Expected
        end

        expect(Rails.logger).to have_received(:error).with(/still not accessible.*after 3 retries/)
      end

      it "uses exponential backoff (10s, 20s, 30s)" do
        begin
          service.send(:add_calendar_to_user_list_for_email, calendar_id, email)
        rescue Google::Apis::ClientError
          # Expected
        end

        expect(service).to have_received(:sleep).with(10).ordered
        expect(service).to have_received(:sleep).with(20).ordered
        expect(service).to have_received(:sleep).with(30).ordered
      end
    end

    context "when other errors occur" do
      before do
        allow(mock_service).to receive(:insert_calendar_list).and_raise(
          Google::Apis::ClientError.new("Server Error", status_code: 500)
        )
      end

      it "raises the error immediately without retrying" do
        expect do
          service.send(:add_calendar_to_user_list_for_email, calendar_id, email)
        end.to raise_error(Google::Apis::ClientError)

        expect(mock_service).to have_received(:insert_calendar_list).once
      end
    end

    context "when credential is not found" do
      before do
        allow(user).to receive(:google_credential_for_email).with(email).and_return(nil)
        allow(mock_service).to receive(:insert_calendar_list)
      end

      it "returns early without attempting to add calendar" do
        service.send(:add_calendar_to_user_list_for_email, calendar_id, email)

        expect(mock_service).not_to have_received(:insert_calendar_list)
      end
    end
  end
end
