# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendarService do
  let(:user) { create(:user) }
  let(:oauth_credential) { create(:oauth_credential, user: user) }
  let(:google_calendar) { create(:google_calendar, oauth_credential: oauth_credential) }
  let(:service) { described_class.new(user) }
  
  describe "#user_edited_event?" do
    let(:db_event) do
      create(:google_calendar_event,
             user: user,
             google_calendar: google_calendar,
             google_event_id: "test_event_123",
             summary: "Original Course Title",
             location: "Room 101",
             start_time: Time.zone.parse("2025-01-15 09:00:00"),
             end_time: Time.zone.parse("2025-01-15 10:30:00"),
             recurrence: ["RRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20250515T235959Z"],
             event_data_hash: "original_hash")
    end
    
    let(:gcal_event) do
      double("Google::Apis::CalendarV3::Event",
             summary: "Original Course Title",
             location: "Room 101",
             start: double(date_time: "2025-01-15T09:00:00-05:00", date: nil),
             end: double(date_time: "2025-01-15T10:30:00-05:00", date: nil),
             recurrence: ["RRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20250515T235959Z"])
    end
    
    context "when user has not edited the event" do
      it "returns false" do
        expect(service.send(:user_edited_event?, db_event, gcal_event)).to be false
      end
    end
    
    context "when user edited the summary" do
      before do
        allow(gcal_event).to receive(:summary).and_return("User Modified Title")
      end
      
      it "returns true" do
        expect(service.send(:user_edited_event?, db_event, gcal_event)).to be true
      end
    end
    
    context "when user edited the location" do
      before do
        allow(gcal_event).to receive(:location).and_return("Room 202 - User Changed")
      end
      
      it "returns true" do
        expect(service.send(:user_edited_event?, db_event, gcal_event)).to be true
      end
    end
    
    context "when user edited the start time" do
      before do
        allow(gcal_event).to receive(:start).and_return(
          double(date_time: "2025-01-15T10:00:00-05:00", date: nil)
        )
      end
      
      it "returns true" do
        expect(service.send(:user_edited_event?, db_event, gcal_event)).to be true
      end
    end
    
    context "when user edited the end time" do
      before do
        allow(gcal_event).to receive(:end).and_return(
          double(date_time: "2025-01-15T11:30:00-05:00", date: nil)
        )
      end
      
      it "returns true" do
        expect(service.send(:user_edited_event?, db_event, gcal_event)).to be true
      end
    end
    
    context "when user edited the recurrence" do
      before do
        allow(gcal_event).to receive(:recurrence).and_return(
          ["RRULE:FREQ=WEEKLY;BYDAY=TU;UNTIL=20250515T235959Z"]
        )
      end
      
      it "returns true" do
        expect(service.send(:user_edited_event?, db_event, gcal_event)).to be true
      end
    end
  end
  
  describe "#update_db_from_gcal_event" do
    let(:db_event) do
      create(:google_calendar_event,
             user: user,
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
      freeze_time do
        service.send(:update_db_from_gcal_event, db_event, gcal_event)
        
        db_event.reload
        expect(db_event.last_synced_at).to be_within(1.second).of(Time.current)
      end
    end
  end
  
  describe "#parse_gcal_time" do
    context "with date_time" do
      let(:time_obj) { double(date_time: "2025-01-15T09:00:00-05:00", date: nil) }
      
      it "parses the datetime to Eastern timezone" do
        result = service.send(:parse_gcal_time, time_obj)
        expect(result).to be_a(Time)
        expect(result.zone).to eq("EST")
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
             user: user,
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
    
    context "when user has edited the event in Google Calendar" do
      let(:gcal_event) do
        double("Google::Apis::CalendarV3::Event",
               summary: "User Modified Title in GCal",
               location: "Room 999 - User Changed",
               start: double(date_time: "2025-01-15T09:00:00-05:00", date: nil),
               end: double(date_time: "2025-01-15T10:30:00-05:00", date: nil),
               recurrence: ["RRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20250515T235959Z"])
      end
      
      before do
        allow(service).to receive(:service_account_calendar_service).and_return(mock_service)
        allow(mock_service).to receive(:get_event).with(
          google_calendar.google_calendar_id,
          db_event.google_event_id
        ).and_return(gcal_event)
      end
      
      it "preserves user's Google Calendar edits and does not overwrite them" do
        service.send(:update_event_in_calendar, mock_service, google_calendar, db_event, course_event)
        
        db_event.reload
        # Should have user's edits, not the system's update
        expect(db_event.summary).to eq("User Modified Title in GCal")
        expect(db_event.location).to eq("Room 999 - User Changed")
        expect(mock_service).not_to have_received(:update_event)
      end
      
      it "marks the event as synced" do
        freeze_time do
          service.send(:update_event_in_calendar, mock_service, google_calendar, db_event, course_event)
          
          db_event.reload
          expect(db_event.last_synced_at).to be_within(1.second).of(Time.current)
        end
      end
    end
    
    context "when user has not edited the event" do
      let(:gcal_event) do
        double("Google::Apis::CalendarV3::Event",
               summary: "Original Course Title",
               location: "Room 101",
               start: double(date_time: "2025-01-15T09:00:00-05:00", date: nil),
               end: double(date_time: "2025-01-15T10:30:00-05:00", date: nil),
               recurrence: ["RRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20250515T235959Z"])
      end
      
      let(:updated_gcal_event) do
        double("Google::Apis::CalendarV3::Event", id: db_event.google_event_id)
      end
      
      before do
        allow(service).to receive(:service_account_calendar_service).and_return(mock_service)
        allow(service).to receive(:get_color_for_meeting_time).and_return("5")
        allow(mock_service).to receive(:get_event).with(
          google_calendar.google_calendar_id,
          db_event.google_event_id
        ).and_return(gcal_event)
        allow(mock_service).to receive(:update_event).and_return(updated_gcal_event)
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
  end
end
