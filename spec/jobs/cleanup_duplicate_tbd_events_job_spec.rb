# frozen_string_literal: true

require "rails_helper"

RSpec.describe CleanupDuplicateTbdEventsJob, type: :job do
  let(:user) { create(:user) }
  let(:oauth_credential) { create(:oauth_credential, user: user) }
  let(:google_calendar) { create(:google_calendar, oauth_credential: oauth_credential) }
  let(:course) { create(:course) }
  let(:enrollment) { create(:enrollment, user: user, course: course) }
  
  let(:tbd_building) { create(:building, name: "To Be Determined", abbreviation: "TBD") }
  let(:valid_building) { create(:building, name: "Watson Hall", abbreviation: "WAT") }
  let(:tbd_room) { create(:room, building: tbd_building, number: "000") }
  let(:valid_room) { create(:room, building: valid_building, number: "101") }

  # Shared dates for meeting times to be considered duplicates
  let(:shared_start_date) { 3.days.from_now.beginning_of_day }
  let(:shared_end_date) { 3.months.from_now.beginning_of_day }

  let(:meeting_time_tbd) do
    create(:meeting_time,
      course: course,
      room: tbd_room,
      day_of_week: "monday",
      begin_time: 900,
      end_time: 1050,
      start_date: shared_start_date,
      end_date: shared_end_date
    )
  end

  let(:meeting_time_valid) do
    create(:meeting_time,
      course: course,
      room: valid_room,
      day_of_week: "monday",
      begin_time: 900,
      end_time: 1050,
      start_date: shared_start_date,
      end_date: shared_end_date
    )
  end

  let(:google_event_tbd) do
    create(:google_calendar_event,
      google_calendar: google_calendar,
      meeting_time: meeting_time_tbd,
      google_event_id: "tbd_event_123"
    )
  end

  let(:google_event_valid) do
    create(:google_calendar_event,
      google_calendar: google_calendar,
      meeting_time: meeting_time_valid,
      google_event_id: "valid_event_456"
    )
  end

  describe "#perform" do
    let(:google_calendar_service) { instance_double(GoogleCalendarService) }
    let(:api_service) { instance_double(Google::Apis::CalendarV3::CalendarService) }

    before do
      allow(GoogleCalendarService).to receive(:new).with(user).and_return(google_calendar_service)
      allow(google_calendar_service).to receive(:send).with(:user_calendar_service).and_return(api_service)
    end

    context "when user has duplicate events (TBD and valid location)" do
      before do
        enrollment
        google_event_tbd
        google_event_valid
      end

      it "deletes the TBD event from Google Calendar" do
        expect(api_service).to receive(:delete_event).with(google_calendar.google_calendar_id, "tbd_event_123")
        
        described_class.perform_now(user.id)
      end

      it "removes the TBD event from the database" do
        allow(api_service).to receive(:delete_event)
        
        expect { described_class.perform_now(user.id) }
          .to change { GoogleCalendarEvent.count }.by(-1)
        
        expect(GoogleCalendarEvent.exists?(google_event_tbd.id)).to be false
        expect(GoogleCalendarEvent.exists?(google_event_valid.id)).to be true
      end

      it "keeps the valid event" do
        allow(api_service).to receive(:delete_event)
        
        described_class.perform_now(user.id)
        
        expect(google_event_valid.reload).to be_present
      end
    end

    context "when event is already deleted from Google" do
      before do
        enrollment
        google_event_tbd
        google_event_valid
        
        allow(api_service).to receive(:delete_event).and_raise(
          Google::Apis::ClientError.new("notFound", status_code: 404)
        )
      end

      it "still removes the event from the database" do
        expect { described_class.perform_now(user.id) }
          .to change { GoogleCalendarEvent.count }.by(-1)
          
        expect(GoogleCalendarEvent.exists?(google_event_tbd.id)).to be false
      end
    end

    context "when there are only TBD events (no valid location events)" do
      before do
        enrollment
        google_event_tbd
      end

      it "does not delete any events" do
        expect(api_service).not_to receive(:delete_event)
        
        expect { described_class.perform_now(user.id) }
          .not_to change { GoogleCalendarEvent.count }
      end
    end

    context "when processing all users" do
      let(:user2) { create(:user) }
      let(:oauth_credential2) { create(:oauth_credential, user: user2) }
      let(:google_calendar2) { create(:google_calendar, oauth_credential: oauth_credential2) }

      before do
        enrollment
        google_event_tbd
        google_event_valid

        # Set up second user with both TBD and valid events
        create(:enrollment, user: user2, course: course)
        create(:google_calendar_event,
          google_calendar: google_calendar2,
          meeting_time: meeting_time_tbd,
          google_event_id: "tbd_event_789"
        )
        create(:google_calendar_event,
          google_calendar: google_calendar2,
          meeting_time: meeting_time_valid,
          google_event_id: "valid_event_790"
        )

        allow(GoogleCalendarService).to receive(:new).with(user2).and_return(google_calendar_service)
        allow(api_service).to receive(:delete_event)
      end

      it "processes all users when no user_id is provided" do
        expect(api_service).to receive(:delete_event).at_least(:twice)
        
        described_class.perform_now
      end
    end
  end
end