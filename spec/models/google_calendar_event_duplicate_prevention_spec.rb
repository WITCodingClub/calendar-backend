# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendarEvent, type: :model do
  describe "duplicate prevention" do
    let(:user) { create(:user, :with_google_credential) }
    let(:google_calendar) { create(:google_calendar, oauth_credential: user.oauth_credentials.first) }
    let(:course) { create(:course) }
    let(:meeting_time) { create(:meeting_time, course: course) }
    let(:final_exam) { create(:final_exam, course: course) }
    let(:university_event) { create(:university_calendar_event, :holiday) }
    
    describe "database constraints" do
      it "prevents duplicate meeting time events for the same calendar" do
        create(:google_calendar_event, google_calendar: google_calendar, meeting_time: meeting_time)
        
        duplicate = build(:google_calendar_event, 
                         google_calendar: google_calendar, 
                         meeting_time: meeting_time)
        
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:meeting_time_id]).to include("has already been taken")
      end
      
      it "prevents duplicate final exam events for the same calendar" do
        create(:google_calendar_event, :with_final_exam, google_calendar: google_calendar, final_exam: final_exam)

        duplicate = build(:google_calendar_event, :with_final_exam,
                         google_calendar: google_calendar,
                         final_exam: final_exam)

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:final_exam_id]).to include("has already been taken")
      end

      it "prevents duplicate university events for the same calendar" do
        create(:google_calendar_event, :with_university_calendar_event,
               google_calendar: google_calendar,
               university_calendar_event: university_event)

        duplicate = build(:google_calendar_event, :with_university_calendar_event,
                         google_calendar: google_calendar,
                         university_calendar_event: university_event)

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:university_calendar_event_id]).to include("has already been taken")
      end
      
      it "allows same event in different calendars" do
        other_user = create(:user, :with_google_credential)
        other_calendar = create(:google_calendar, oauth_credential: other_user.oauth_credentials.first)
        
        create(:google_calendar_event, google_calendar: google_calendar, meeting_time: meeting_time)
        
        other_event = build(:google_calendar_event, 
                           google_calendar: other_calendar, 
                           meeting_time: meeting_time)
        
        expect(other_event).to be_valid
      end
    end
    
    describe "only_one_event_type_associated validation" do
      it "requires exactly one event type to be associated" do
        event = build(:google_calendar_event, 
                     google_calendar: google_calendar,
                     meeting_time: nil,
                     final_exam: nil,
                     university_calendar_event: nil)
        
        expect(event).not_to be_valid
        expect(event.errors[:base]).to include("Must be associated with exactly one of: meeting_time, final_exam, or university_calendar_event")
      end
      
      it "prevents multiple event types from being associated" do
        event = build(:google_calendar_event, 
                     google_calendar: google_calendar,
                     meeting_time: meeting_time,
                     final_exam: final_exam)
        
        expect(event).not_to be_valid
        expect(event.errors[:base]).to include("Must be associated with exactly one of: meeting_time, final_exam, or university_calendar_event")
      end
    end
  end
end