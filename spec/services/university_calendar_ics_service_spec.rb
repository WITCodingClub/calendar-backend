# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe UniversityCalendarIcsService, type: :service do
  let(:ics_content) { Rails.root.join("spec/fixtures/files/university_calendar.ics").read }
  let(:ics_url) { "https://25livepub.collegenet.com/calendars/wit-main-events-calendar.ics" }

  before do
    stub_request(:get, ics_url)
      .to_return(status: 200, body: ics_content, headers: { "Content-Type" => "text/calendar" })
  end

  describe "#call" do
    it "parses ICS events and creates records" do
      expect { described_class.call }.to change(UniversityCalendarEvent, :count).by(6)
    end

    it "returns statistics about the sync" do
      result = described_class.call

      expect(result[:created]).to eq(6)
      expect(result[:updated]).to eq(0)
      expect(result[:unchanged]).to eq(0)
      expect(result[:errors]).to be_empty
    end

    it "updates existing events on subsequent runs" do
      # First run creates events
      described_class.call
      expect(UniversityCalendarEvent.count).to eq(6)

      # Second run should find them unchanged
      result = described_class.call
      expect(result[:created]).to eq(0)
      expect(result[:unchanged]).to eq(6)
    end

    it "updates events when content changes" do
      described_class.call
      event = UniversityCalendarEvent.find_by(ics_uid: "event-fall-classes-begin@university.edu")

      # Simulate a change in the ICS content
      modified_content = ics_content.gsub("Fall 2025 Classes Begin", "Fall 2025 Classes Start")
      stub_request(:get, ics_url)
        .to_return(status: 200, body: modified_content)

      result = described_class.call
      expect(result[:updated]).to eq(1)
      expect(event.reload.summary).to eq("Fall 2025 Classes Start")
    end
  end

  describe "category inference" do
    before { described_class.call }

    it "categorizes holiday events" do
      thanksgiving = UniversityCalendarEvent.find_by(ics_uid: "event-thanksgiving@university.edu")
      labor_day = UniversityCalendarEvent.find_by(ics_uid: "event-labor-day@university.edu")

      expect(thanksgiving.category).to eq("holiday")
      expect(labor_day.category).to eq("holiday")
    end

    it "categorizes academic events" do
      classes_begin = UniversityCalendarEvent.find_by(ics_uid: "event-fall-classes-begin@university.edu")
      finals = UniversityCalendarEvent.find_by(ics_uid: "event-fall-finals@university.edu")

      expect(classes_begin.category).to eq("academic")
      expect(finals.category).to eq("academic")
    end

    it "categorizes meeting events" do
      board_meeting = UniversityCalendarEvent.find_by(ics_uid: "event-board-meeting@university.edu")
      expect(board_meeting.category).to eq("meeting")
    end

    it "categorizes other events as campus_event" do
      tour = UniversityCalendarEvent.find_by(ics_uid: "event-campus-tour@university.edu")
      expect(tour.category).to eq("campus_event")
    end
  end

  describe "custom field extraction" do
    before { described_class.call }

    it "extracts Academic Term" do
      event = UniversityCalendarEvent.find_by(ics_uid: "event-fall-classes-begin@university.edu")
      expect(event.academic_term).to eq("Fall")
    end

    it "extracts Organization" do
      event = UniversityCalendarEvent.find_by(ics_uid: "event-campus-tour@university.edu")
      expect(event.organization).to eq("Admissions Office")
    end

    it "extracts Event Type" do
      event = UniversityCalendarEvent.find_by(ics_uid: "event-fall-classes-begin@university.edu")
      expect(event.event_type_raw).to eq("Calendar Announcement")
    end
  end

  describe "all-day event detection" do
    before { described_class.call }

    it "marks DATE events as all-day" do
      thanksgiving = UniversityCalendarEvent.find_by(ics_uid: "event-thanksgiving@university.edu")
      expect(thanksgiving.all_day).to be true
    end

    it "marks DATETIME events as not all-day" do
      tour = UniversityCalendarEvent.find_by(ics_uid: "event-campus-tour@university.edu")
      expect(tour.all_day).to be false
    end
  end

  describe "time parsing" do
    before { described_class.call }

    it "parses all-day event dates correctly" do
      event = UniversityCalendarEvent.find_by(ics_uid: "event-thanksgiving@university.edu")
      expect(event.start_time.to_date).to eq(Date.new(2025, 11, 27))
      expect(event.end_time.to_date).to eq(Date.new(2025, 12, 1))
    end

    it "parses timed events correctly" do
      event = UniversityCalendarEvent.find_by(ics_uid: "event-campus-tour@university.edu")
      expect(event.start_time).to be_present
      expect(event.end_time).to be_present
      expect(event.end_time).to be > event.start_time
    end
  end

  describe "location extraction" do
    before { described_class.call }

    it "extracts location from events" do
      event = UniversityCalendarEvent.find_by(ics_uid: "event-campus-tour@university.edu")
      expect(event.location).to eq("Main Entrance")
    end

    it "handles events without location" do
      event = UniversityCalendarEvent.find_by(ics_uid: "event-thanksgiving@university.edu")
      expect(event.location).to be_nil
    end
  end

  describe "term linking" do
    let!(:fall_term) { create(:term, year: 2025, season: :fall) }

    before { described_class.call }

    it "links events to matching terms" do
      event = UniversityCalendarEvent.find_by(ics_uid: "event-fall-classes-begin@university.edu")
      expect(event.term).to eq(fall_term)
    end

    it "does not link events without academic_term" do
      event = UniversityCalendarEvent.find_by(ics_uid: "event-labor-day@university.edu")
      expect(event.term).to be_nil
    end
  end

  describe "error handling" do
    it "handles network errors gracefully" do
      stub_request(:get, ics_url).to_timeout

      expect { described_class.call }.to raise_error(Faraday::ConnectionFailed)
    end

    it "handles HTTP errors" do
      stub_request(:get, ics_url).to_return(status: 500)

      expect { described_class.call }.to raise_error(/Failed to fetch ICS feed: 500/)
    end

    it "handles malformed ICS content" do
      stub_request(:get, ics_url)
        .to_return(status: 200, body: "not valid ics content")

      result = described_class.call
      expect(result[:created]).to eq(0)
      expect(result[:errors]).to be_empty
    end
  end

  describe "webcal URL conversion" do
    it "converts webcal:// to https://" do
      webcal_url = "webcal://25livepub.collegenet.com/calendars/wit-main-events-calendar.ics"
      https_url = "https://25livepub.collegenet.com/calendars/wit-main-events-calendar.ics"

      stub_request(:get, https_url)
        .to_return(status: 200, body: ics_content)

      expect { described_class.call(ics_url: webcal_url) }.to change(UniversityCalendarEvent, :count)
    end
  end

  describe "source URL tracking" do
    before { described_class.call }

    it "records the source URL on events" do
      event = UniversityCalendarEvent.first
      expect(event.source_url).to eq(ics_url)
    end
  end
end
