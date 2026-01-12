# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendarService, "#update_specific_events with event preferences" do
  let(:user) { create(:user) }
  let(:oauth_credential) { create(:oauth_credential, user: user) }
  let(:google_calendar) { create(:google_calendar, oauth_credential: oauth_credential) }
  let(:term) { create(:term) }
  let(:course) { create(:course, term: term, schedule_type: "lecture") }
  let(:meeting_time) { create(:meeting_time, course: course) }
  let(:service) { described_class.new(user) }

  let(:mock_calendar_service) { instance_double(Google::Apis::CalendarV3::CalendarService) }
  let(:mock_google_event) { instance_double(Google::Apis::CalendarV3::Event, id: "event123") }

  before do
    # Mock the Google Calendar service
    allow(service).to receive(:user_calendar_service).and_return(mock_calendar_service)
    allow(user).to receive(:google_credential).and_return(oauth_credential)

    # Mock initial event creation
    allow(mock_calendar_service).to receive_messages(insert_event: mock_google_event, update_event: mock_google_event)
  end

  describe "updating event color via EventPreference" do
    let!(:existing_event) do
      create(:google_calendar_event,
             google_calendar: google_calendar,
             meeting_time: meeting_time,
             google_event_id: "event123",
             summary: course.title,
             location: "Building - Room",
             start_time: 1.day.from_now.change(hour: 9),
             end_time: 1.day.from_now.change(hour: 10),
             event_data_hash: GoogleCalendarEvent.generate_data_hash({
                                                                       summary: course.title,
                                                                       location: "Building - Room",
                                                                       start_time: 1.day.from_now.change(hour: 9),
                                                                       end_time: 1.day.from_now.change(hour: 10),
                                                                       recurrence: nil,
                                                                       reminder_settings: nil,
                                                                       color_id: nil,
                                                                       visibility: nil
                                                                     }))
    end

    let(:event_data) do
      {
        summary: course.title,
        description: "DESC",
        location: "Building - Room",
        start_time: 1.day.from_now.change(hour: 9),
        end_time: 1.day.from_now.change(hour: 10),
        meeting_time_id: meeting_time.id,
        recurrence: nil
      }
    end

    context "when EventPreference with color is created" do
      before do
        # Create an event preference with a specific color
        EventPreference.create!(
          user: user,
          preferenceable: meeting_time,
          color_id: 7 # Blue
        )
      end

      it "updates the Google Calendar event with the new color" do
        service.update_specific_events([event_data], force: true)

        expect(mock_calendar_service).to have_received(:update_event) do |calendar_id, event_id, google_event|
          expect(event_id).to eq("event123")
          expect(google_event.color_id).to eq("7")
        end
      end

      it "updates the database event_data_hash to include the new color" do
        old_hash = existing_event.event_data_hash

        service.update_specific_events([event_data], force: true)

        existing_event.reload

        # Hash should have changed due to color preference
        expect(existing_event.event_data_hash).not_to eq(old_hash)

        # Verify the hash was actually updated
        expect(existing_event.event_data_hash).to be_present
      end
    end

    context "when EventPreference color is updated from one color to another" do
      let!(:event_preference) do
        EventPreference.create!(
          user: user,
          preferenceable: meeting_time,
          color_id: 5 # Purple initially
        )
      end

      before do
        # Update the existing event's hash to reflect the initial color
        existing_event.update_column(:event_data_hash, GoogleCalendarEvent.generate_data_hash({
                                                                                                summary: course.title,
                                                                                                location: "Building - Room",
                                                                                                start_time: 1.day.from_now.change(hour: 9),
                                                                                                end_time: 1.day.from_now.change(hour: 10),
                                                                                                recurrence: nil,
                                                                                                reminder_settings: [{ "time" => "30", "type" => "minutes", "method" => "popup" }],
                                                                                                color_id: 5,
                                                                                                visibility: "default"
                                                                                              }))
      end

      it "updates the Google Calendar event with the new color when preference is updated" do
        # Update the preference to a different color
        event_preference.update!(color_id: 7) # Change to Blue

        service.update_specific_events([event_data], force: true)

        expect(mock_calendar_service).to have_received(:update_event) do |calendar_id, event_id, google_event|
          expect(event_id).to eq("event123")
          expect(google_event.color_id).to eq("7"), "Expected Google Calendar event to be updated with color_id '7'"
        end
      end
    end
  end
end
