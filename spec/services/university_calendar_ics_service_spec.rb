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
      expect { described_class.call }.to change(UniversityCalendarEvent, :count).by(8)
    end

    it "returns statistics about the sync" do
      result = described_class.call

      expect(result[:created]).to eq(8)
      expect(result[:updated]).to eq(0)
      expect(result[:unchanged]).to eq(0)
      expect(result[:errors]).to be_empty
    end

    it "updates existing events on subsequent runs" do
      # First run creates events
      described_class.call
      expect(UniversityCalendarEvent.count).to eq(8)

      # Second run should find them unchanged
      result = described_class.call
      expect(result[:created]).to eq(0)
      expect(result[:unchanged]).to eq(8)
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

    it "categorizes term dates events" do
      classes_begin = UniversityCalendarEvent.find_by(ics_uid: "event-fall-classes-begin@university.edu")
      expect(classes_begin.category).to eq("term_dates")
    end

    it "categorizes finals events" do
      finals = UniversityCalendarEvent.find_by(ics_uid: "event-fall-finals@university.edu")
      expect(finals.category).to eq("finals")
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

    it "prefers Event Name custom field over ICS summary when available" do
      # The ICS summary has "DayHoliday" without space, but Event Name custom field has correct spacing
      event = UniversityCalendarEvent.find_by(ics_uid: "event-mlk-day@university.edu")
      expect(event.summary).to eq("Martin Luther King Jr. Day Holiday")
      expect(event.summary).not_to include("DayHoliday")
    end

    it "falls back to ICS summary when Event Name custom field is not present" do
      # Thanksgiving event has no Event Name custom field
      event = UniversityCalendarEvent.find_by(ics_uid: "event-thanksgiving@university.edu")
      expect(event.summary).to eq("Thanksgiving Break - No Classes")
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
    let!(:fall_term) { create(:term, year: 2025, season: :fall, start_date: Date.new(2025, 8, 15), end_date: Date.new(2025, 12, 20)) }

    before { described_class.call }

    it "links events to matching terms via academic_term" do
      event = UniversityCalendarEvent.find_by(ics_uid: "event-fall-classes-begin@university.edu")
      expect(event.term).to eq(fall_term)
    end

    it "links events without academic_term using date-based fallback" do
      # Labor Day (Sept 1, 2025) falls within fall term dates
      event = UniversityCalendarEvent.find_by(ics_uid: "event-labor-day@university.edu")
      expect(event.term).to eq(fall_term)
    end

    it "does not link events when date is outside all term ranges" do
      # Create event outside any term range
      summer_event = UniversityCalendarEvent.find_by(ics_uid: "event-campus-tour@university.edu")
      # Campus tour is Oct 1, 2025 which IS in fall term range, so it should be linked
      expect(summer_event.term).to eq(fall_term)
    end
  end

  describe "term mismatch detection for term_dates events" do
    let!(:spring_term) { create(:term, year: 2026, season: :spring, start_date: Date.new(2026, 1, 6), end_date: Date.new(2026, 5, 10)) }
    let!(:summer_term) { create(:term, year: 2026, season: :summer, start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 7, 31)) }

    before do
      # Capture Rails logger output to verify warnings
      allow(Rails.logger).to receive(:warn)
      described_class.call
    end

    it "corrects term association when ICS academic_term is wrong for term_dates events" do
      # The "Last Day of Classes" event is on May 5, 2026 (clearly Spring)
      # but the ICS feed incorrectly labels it as "Summer"
      event = UniversityCalendarEvent.find_by(ics_uid: "event-spring-classes-end@university.edu")

      # Should be linked to Spring 2026, NOT Summer 2026
      expect(event.term).to eq(spring_term)
      expect(event.term).not_to eq(summer_term)
    end

    it "logs a warning when term mismatch is detected" do
      expect(Rails.logger).to have_received(:warn).with(
        a_string_matching(/Term mismatch detected/)
          .and(matching(/ICS claims 'Summer'/))
          .and(matching(/suggests Spring 2026/))
          .and(matching(/Last Day of Classes/))
      )
    end

    it "stores the original academic_term value from ICS" do
      event = UniversityCalendarEvent.find_by(ics_uid: "event-spring-classes-end@university.edu")
      # The academic_term field stores what the ICS feed said (for auditing)
      expect(event.academic_term).to eq("Summer")
    end

    it "correctly infers Spring term for events in January-May" do
      event = UniversityCalendarEvent.find_by(ics_uid: "event-spring-classes-end@university.edu")
      expect(event.start_time.month).to be_between(1, 5)
      expect(event.term&.season).to eq("spring")
    end

    it "does not affect non-term_dates events" do
      # Holiday events should still use the original logic
      mlk_event = UniversityCalendarEvent.find_by(ics_uid: "event-mlk-day@university.edu")
      expect(mlk_event.category).to eq("holiday")
      # MLK Day is in January (Spring) and labeled as "Spring", so should match
      expect(mlk_event.term).to eq(spring_term)
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

  describe "multi-day event merging" do
    let(:spring_break_ics) do
      <<~ICS
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//Test//EN
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20250310
        DTEND;VALUE=DATE:20250311
        DTSTAMP:20251224T000000Z
        UID:event-spring-break-day1@university.edu
        SUMMARY:Spring Break - No Classes
        X-TRUMBA-CUSTOMFIELD;NAME="Academic Term";ID=1;TYPE=SingleLine:Spring
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20250311
        DTEND;VALUE=DATE:20250312
        DTSTAMP:20251224T000000Z
        UID:event-spring-break-day2@university.edu
        SUMMARY:Spring Break - No Classes
        X-TRUMBA-CUSTOMFIELD;NAME="Academic Term";ID=1;TYPE=SingleLine:Spring
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20250312
        DTEND;VALUE=DATE:20250313
        DTSTAMP:20251224T000000Z
        UID:event-spring-break-day3@university.edu
        SUMMARY:Spring Break - No Classes
        X-TRUMBA-CUSTOMFIELD;NAME="Academic Term";ID=1;TYPE=SingleLine:Spring
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20250313
        DTEND;VALUE=DATE:20250314
        DTSTAMP:20251224T000000Z
        UID:event-spring-break-day4@university.edu
        SUMMARY:Spring Break - No Classes
        X-TRUMBA-CUSTOMFIELD;NAME="Academic Term";ID=1;TYPE=SingleLine:Spring
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20250314
        DTEND;VALUE=DATE:20250315
        DTSTAMP:20251224T000000Z
        UID:event-spring-break-day5@university.edu
        SUMMARY:Spring Break - No Classes
        X-TRUMBA-CUSTOMFIELD;NAME="Academic Term";ID=1;TYPE=SingleLine:Spring
        END:VEVENT
        END:VCALENDAR
      ICS
    end

    it "merges consecutive same-named all-day events into single multi-day event" do
      stub_request(:get, ics_url)
        .to_return(status: 200, body: spring_break_ics)

      expect { described_class.call }.to change(UniversityCalendarEvent, :count).by(1)

      event = UniversityCalendarEvent.first
      expect(event.summary).to eq("Spring Break - No Classes")
      expect(event.start_time.to_date).to eq(Date.new(2025, 3, 10))
      # ICS DTEND is preserved as-is; the last VEVENT has DTEND:20250315
      expect(event.end_time.to_date).to eq(Date.new(2025, 3, 15))
      expect(event.all_day).to be true
      expect(event.ics_uid).to start_with("merged:")
    end

    it "returns merged count in stats" do
      stub_request(:get, ics_url)
        .to_return(status: 200, body: spring_break_ics)

      result = described_class.call

      expect(result[:merged]).to eq(4) # 5 events merged into 1, so 4 merged away
      expect(result[:created]).to eq(1)
    end

    context "with non-consecutive events" do
      let(:non_consecutive_ics) do
        <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          PRODID:-//Test//Test//EN
          BEGIN:VEVENT
          DTSTART;VALUE=DATE:20250310
          DTEND;VALUE=DATE:20250311
          DTSTAMP:20251224T000000Z
          UID:event-break1@university.edu
          SUMMARY:Study Break - No Classes
          X-TRUMBA-CUSTOMFIELD;NAME="Academic Term";ID=1;TYPE=SingleLine:Spring
          END:VEVENT
          BEGIN:VEVENT
          DTSTART;VALUE=DATE:20250315
          DTEND;VALUE=DATE:20250316
          DTSTAMP:20251224T000000Z
          UID:event-break2@university.edu
          SUMMARY:Study Break - No Classes
          X-TRUMBA-CUSTOMFIELD;NAME="Academic Term";ID=1;TYPE=SingleLine:Spring
          END:VEVENT
          END:VCALENDAR
        ICS
      end

      it "does not merge events with gaps between them" do
        stub_request(:get, ics_url)
          .to_return(status: 200, body: non_consecutive_ics)

        expect { described_class.call }.to change(UniversityCalendarEvent, :count).by(2)
      end
    end

    context "with different event names on consecutive days" do
      let(:different_names_ics) do
        <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          PRODID:-//Test//Test//EN
          BEGIN:VEVENT
          DTSTART;VALUE=DATE:20250310
          DTEND;VALUE=DATE:20250311
          DTSTAMP:20251224T000000Z
          UID:event-spring-break@university.edu
          SUMMARY:Spring Break - No Classes
          END:VEVENT
          BEGIN:VEVENT
          DTSTART;VALUE=DATE:20250311
          DTEND;VALUE=DATE:20250312
          DTSTAMP:20251224T000000Z
          UID:event-different-event@university.edu
          SUMMARY:Different Event
          END:VEVENT
          END:VCALENDAR
        ICS
      end

      it "does not merge events with different summaries" do
        stub_request(:get, ics_url)
          .to_return(status: 200, body: different_names_ics)

        expect { described_class.call }.to change(UniversityCalendarEvent, :count).by(2)
      end
    end

    context "with non-all-day events" do
      let(:timed_events_ics) do
        <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          PRODID:-//Test//Test//EN
          BEGIN:VEVENT
          DTSTART:20250310T140000
          DTEND:20250310T160000
          DTSTAMP:20251224T000000Z
          UID:event-meeting1@university.edu
          SUMMARY:Daily Standup
          END:VEVENT
          BEGIN:VEVENT
          DTSTART:20250311T140000
          DTEND:20250311T160000
          DTSTAMP:20251224T000000Z
          UID:event-meeting2@university.edu
          SUMMARY:Daily Standup
          END:VEVENT
          END:VCALENDAR
        ICS
      end

      it "does not merge non-all-day events" do
        stub_request(:get, ics_url)
          .to_return(status: 200, body: timed_events_ics)

        expect { described_class.call }.to change(UniversityCalendarEvent, :count).by(2)
      end
    end

    context "when updating existing single-day events to merged" do
      let(:spring_break_single_ics) do
        <<~ICS
          BEGIN:VCALENDAR
          VERSION:2.0
          PRODID:-//Test//Test//EN
          BEGIN:VEVENT
          DTSTART;VALUE=DATE:20250310
          DTEND;VALUE=DATE:20250311
          DTSTAMP:20251224T000000Z
          UID:event-spring-break-day1@university.edu
          SUMMARY:Spring Break - No Classes
          END:VEVENT
          END:VCALENDAR
        ICS
      end

      it "cleans up old single-day events when merging" do
        # First, create a single-day event
        stub_request(:get, ics_url)
          .to_return(status: 200, body: spring_break_single_ics)
        described_class.call
        expect(UniversityCalendarEvent.count).to eq(1)
        original_event = UniversityCalendarEvent.first
        expect(original_event.ics_uid).to eq("event-spring-break-day1@university.edu")

        # Now feed comes with multiple consecutive days (simulating calendar update)
        stub_request(:get, ics_url)
          .to_return(status: 200, body: spring_break_ics)

        described_class.call

        # Should still have 1 event, but now multi-day
        expect(UniversityCalendarEvent.count).to eq(1)
        merged_event = UniversityCalendarEvent.first
        expect(merged_event.start_time.to_date).to eq(Date.new(2025, 3, 10))
        # ICS DTEND is preserved as-is; the last VEVENT has DTEND:20250315
        expect(merged_event.end_time.to_date).to eq(Date.new(2025, 3, 15))
        expect(merged_event.ics_uid).to start_with("merged:")
      end
    end
  end

  describe "duplicate event detection" do
    # Test for non-all-day event duplicates (which won't be merged by consecutive event logic)
    let(:duplicate_meeting_ics) do
      <<~ICS
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//Test//EN
        BEGIN:VEVENT
        DTSTART:20250310T140000
        DTEND:20250310T160000
        DTSTAMP:20251224T000000Z
        UID:event-board-meeting-1@university.edu
        SUMMARY:Board of Trustees Meeting
        X-TRUMBA-CUSTOMFIELD;NAME="Event Type";ID=2;TYPE=SingleLine:Meeting
        END:VEVENT
        BEGIN:VEVENT
        DTSTART:20250310T140000
        DTEND:20250310T160000
        DTSTAMP:20251224T000000Z
        UID:event-board-meeting-2@university.edu
        SUMMARY:Board of Trustees Meeting
        X-TRUMBA-CUSTOMFIELD;NAME="Event Type";ID=2;TYPE=SingleLine:Meeting
        END:VEVENT
        END:VCALENDAR
      ICS
    end

    it "skips duplicate non-all-day events with different UIDs but same content" do
      stub_request(:get, ics_url)
        .to_return(status: 200, body: duplicate_meeting_ics)

      # Should only create 1 event, skipping the duplicate
      expect { described_class.call }.to change(UniversityCalendarEvent, :count).by(1)

      event = UniversityCalendarEvent.first
      expect(event.summary).to eq("Board of Trustees Meeting")
      expect(event.category).to eq("meeting")
    end

    it "reports skipped duplicates in stats" do
      stub_request(:get, ics_url)
        .to_return(status: 200, body: duplicate_meeting_ics)

      result = described_class.call

      expect(result[:created]).to eq(1)
      expect(result[:unchanged]).to eq(1) # Second event is skipped as duplicate
    end

    it "keeps existing event and skips new duplicate on subsequent syncs" do
      # First sync with one event
      single_event_ics = <<~ICS
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//Test//EN
        BEGIN:VEVENT
        DTSTART:20250310T140000
        DTEND:20250310T160000
        DTSTAMP:20251224T000000Z
        UID:event-meeting-original@university.edu
        SUMMARY:Board of Trustees Meeting
        X-TRUMBA-CUSTOMFIELD;NAME="Event Type";ID=2;TYPE=SingleLine:Meeting
        END:VEVENT
        END:VCALENDAR
      ICS

      stub_request(:get, ics_url)
        .to_return(status: 200, body: single_event_ics)
      described_class.call

      expect(UniversityCalendarEvent.count).to eq(1)
      original_event = UniversityCalendarEvent.first
      expect(original_event.ics_uid).to eq("event-meeting-original@university.edu")

      # Second sync now includes a duplicate with different UID
      stub_request(:get, ics_url)
        .to_return(status: 200, body: duplicate_meeting_ics)

      result = described_class.call

      # Should still have 1 event (original is found unchanged, new duplicate is skipped)
      expect(UniversityCalendarEvent.count).to eq(1)
      expect(result[:unchanged]).to eq(2) # Original event unchanged + duplicate skipped
    end

    # Test that all-day duplicates on same date are handled by merge logic
    it "handles all-day duplicate events via merge logic (not duplicate detection)" do
      duplicate_holiday_ics = <<~ICS
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//Test//EN
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20250310
        DTEND;VALUE=DATE:20250311
        DTSTAMP:20251224T000000Z
        UID:event-wellbeing-1@university.edu
        SUMMARY:Wellbeing Day - No Classes
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20250310
        DTEND;VALUE=DATE:20250311
        DTSTAMP:20251224T000000Z
        UID:event-wellbeing-2@university.edu
        SUMMARY:Wellbeing Day - No Classes
        END:VEVENT
        END:VCALENDAR
      ICS

      stub_request(:get, ics_url)
        .to_return(status: 200, body: duplicate_holiday_ics)

      result = described_class.call

      # These get merged into one event
      expect(UniversityCalendarEvent.count).to eq(1)
      expect(result[:created]).to eq(1)
      expect(result[:merged]).to eq(1) # 2 events -> 1 event = 1 merged

      event = UniversityCalendarEvent.first
      expect(event.ics_uid).to start_with("merged:")
    end
  end

  describe "HTML entity decoding" do
    # Note: In ICS format, semicolons must be escaped with backslash
    # Real ICS feeds from 25Live escape HTML entities this way
    let(:ics_with_html_entities) do
      <<~ICS
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//Test//EN
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20251001
        DTEND;VALUE=DATE:20251002
        DTSTAMP:20251224T000000Z
        UID:event-html-entities@university.edu
        SUMMARY:Arts &amp\\; Sciences Festival
        DESCRIPTION:Join us for an arts &amp\\; sciences event!<br/>Food &amp\\; drinks provided.
        LOCATION:Building A &amp\\; B
        X-TRUMBA-CUSTOMFIELD;NAME="Organization";ID=3;TYPE=SingleLine:Student Government &amp\\; Activities
        X-TRUMBA-CUSTOMFIELD;NAME="Academic Term";ID=1;TYPE=SingleLine:Fall
        X-TRUMBA-CUSTOMFIELD;NAME="Event Type";ID=2;TYPE=SingleLine:Campus Event &ndash\\; General
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20251015
        DTEND;VALUE=DATE:20251016
        DTSTAMP:20251224T000000Z
        UID:event-numeric-entities@university.edu
        SUMMARY:Caf&#233\\; Night &#38\\; More
        DESCRIPTION:Special caf&#233\\; event.
        LOCATION:Room &#35\\;101
        END:VEVENT
        END:VCALENDAR
      ICS
    end

    before do
      stub_request(:get, ics_url)
        .to_return(status: 200, body: ics_with_html_entities)
      described_class.call
    end

    it "decodes &amp; in summary" do
      event = UniversityCalendarEvent.find_by(ics_uid: "event-html-entities@university.edu")
      expect(event.summary).to eq("Arts & Sciences Festival")
    end

    it "decodes &amp; in location" do
      event = UniversityCalendarEvent.find_by(ics_uid: "event-html-entities@university.edu")
      expect(event.location).to eq("Building A & B")
    end

    it "decodes &amp; and HTML tags in description" do
      event = UniversityCalendarEvent.find_by(ics_uid: "event-html-entities@university.edu")
      expect(event.description).to eq("Join us for an arts & sciences event!\nFood & drinks provided.")
    end

    it "decodes &amp; in organization custom field" do
      event = UniversityCalendarEvent.find_by(ics_uid: "event-html-entities@university.edu")
      expect(event.organization).to eq("Student Government & Activities")
    end

    it "decodes &ndash; in event_type_raw custom field" do
      event = UniversityCalendarEvent.find_by(ics_uid: "event-html-entities@university.edu")
      expect(event.event_type_raw).to eq("Campus Event – General")
    end

    it "decodes numeric HTML entities like &#233; and &#38;" do
      event = UniversityCalendarEvent.find_by(ics_uid: "event-numeric-entities@university.edu")
      expect(event.summary).to eq("Café Night & More")
    end

    it "decodes numeric HTML entities in location" do
      event = UniversityCalendarEvent.find_by(ics_uid: "event-numeric-entities@university.edu")
      expect(event.location).to eq("Room #101")
    end
  end
end
