# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseScheduleSyncable do
  # Create a test class that includes the concern
  let(:test_class) do
    Class.new do
      include CourseScheduleSyncable

      attr_accessor :enrollments

      def initialize
        @enrollments = []
      end

      # Stub the oauth credential
      def google_credential
        nil
      end
    end
  end

  let(:instance) { test_class.new }

  describe "#build_recurrence_with_exclusions" do
    let(:term) { create(:term, year: 2024, season: :fall) }
    let(:course) { create(:course, term: term) }
    let(:meeting_time) do
      create(:meeting_time,
             course: course,
             day_of_week: :monday,
             start_date: Date.new(2024, 8, 26),
             end_date: Date.new(2024, 12, 13),
             begin_time: 900,
             end_time: 950)
    end
    let(:start_time) { Time.zone.local(2024, 8, 26, 9, 0, 0) }
    let(:recurrence_rule) { "RRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL=20241213T235959Z" }

    context "when there are no holidays" do
      it "returns just the recurrence rule" do
        result = instance.build_recurrence_with_exclusions(meeting_time, recurrence_rule, start_time)
        expect(result).to eq([recurrence_rule])
      end
    end

    context "when there is no recurrence rule" do
      it "returns nil" do
        result = instance.build_recurrence_with_exclusions(meeting_time, nil, start_time)
        expect(result).to be_nil
      end
    end

    context "when there are holidays on the meeting day" do
      before do
        # Labor Day - Monday, September 2, 2024
        create(:university_calendar_event,
               category: "holiday",
               summary: "Labor Day",
               start_time: Time.zone.local(2024, 9, 2, 0, 0, 0),
               end_time: Time.zone.local(2024, 9, 2, 23, 59, 59),
               all_day: true)

        # Thanksgiving Break - includes Monday Nov 25
        create(:university_calendar_event,
               category: "holiday",
               summary: "Thanksgiving Break",
               start_time: Time.zone.local(2024, 11, 25, 0, 0, 0),
               end_time: Time.zone.local(2024, 11, 25, 23, 59, 59),
               all_day: true)
      end

      it "includes EXDATE entries for holidays on the meeting day" do
        result = instance.build_recurrence_with_exclusions(meeting_time, recurrence_rule, start_time)

        expect(result).to include(recurrence_rule)
        expect(result.size).to eq(3) # RRULE + 2 EXDATEs

        # Check EXDATE format
        timezone = Time.zone.tzinfo.name
        expect(result).to include("EXDATE;TZID=#{timezone}:20240902T090000")
        expect(result).to include("EXDATE;TZID=#{timezone}:20241125T090000")
      end
    end

    context "when holidays fall on different days than the meeting" do
      before do
        # Thanksgiving Day - Thursday, November 28, 2024
        create(:university_calendar_event,
               category: "holiday",
               summary: "Thanksgiving Day",
               start_time: Time.zone.local(2024, 11, 28, 0, 0, 0),
               end_time: Time.zone.local(2024, 11, 28, 23, 59, 59),
               all_day: true)
      end

      it "does not include EXDATE for holidays on other days" do
        result = instance.build_recurrence_with_exclusions(meeting_time, recurrence_rule, start_time)

        expect(result).to eq([recurrence_rule])
      end
    end

    context "when holidays are outside the meeting time date range" do
      before do
        # Holiday before the semester starts
        create(:university_calendar_event,
               category: "holiday",
               summary: "Independence Day",
               start_time: Time.zone.local(2024, 7, 4, 0, 0, 0),
               end_time: Time.zone.local(2024, 7, 4, 23, 59, 59),
               all_day: true)

        # Holiday after the semester ends
        create(:university_calendar_event,
               category: "holiday",
               summary: "Christmas Day",
               start_time: Time.zone.local(2024, 12, 25, 0, 0, 0),
               end_time: Time.zone.local(2024, 12, 25, 23, 59, 59),
               all_day: true)
      end

      it "does not include EXDATE for holidays outside the date range" do
        result = instance.build_recurrence_with_exclusions(meeting_time, recurrence_rule, start_time)

        expect(result).to eq([recurrence_rule])
      end
    end
  end

  describe "#build_holiday_exdates" do
    let(:term) { create(:term, year: 2024, season: :fall) }
    let(:course) { create(:course, term: term) }
    let(:meeting_time) do
      create(:meeting_time,
             course: course,
             day_of_week: :wednesday,
             start_date: Date.new(2024, 8, 28),
             end_date: Date.new(2024, 12, 11),
             begin_time: 1400,
             end_time: 1450)
    end
    let(:start_time) { Time.zone.local(2024, 8, 28, 14, 0, 0) }

    before do
      # Wednesday holiday
      create(:university_calendar_event,
             category: "holiday",
             summary: "Thanksgiving Eve",
             start_time: Time.zone.local(2024, 11, 27, 0, 0, 0),
             end_time: Time.zone.local(2024, 11, 27, 23, 59, 59),
             all_day: true)
    end

    it "returns EXDATE strings with correct timezone and time" do
      result = instance.build_holiday_exdates(meeting_time, start_time)

      timezone = Time.zone.tzinfo.name
      expect(result).to eq(["EXDATE;TZID=#{timezone}:20241127T140000"])
    end

    context "when meeting time day_of_week is nil" do
      let(:meeting_time) do
        create(:meeting_time,
               course: course,
               day_of_week: nil,
               start_date: Date.new(2024, 8, 28),
               end_date: Date.new(2024, 12, 11))
      end

      it "returns an empty array" do
        result = instance.build_holiday_exdates(meeting_time, start_time)
        expect(result).to eq([])
      end
    end
  end

  describe "#holidays_for_meeting_time" do
    let(:term) { create(:term, year: 2024, season: :fall) }
    let(:course) { create(:course, term: term) }
    let(:meeting_time) do
      create(:meeting_time,
             course: course,
             day_of_week: :monday,
             start_date: Date.new(2024, 8, 26),
             end_date: Date.new(2024, 12, 13))
    end

    before do
      # Holiday within range
      create(:university_calendar_event,
             category: "holiday",
             summary: "Labor Day",
             start_time: Time.zone.local(2024, 9, 2, 0, 0, 0),
             end_time: Time.zone.local(2024, 9, 2, 23, 59, 59))

      # Non-holiday event
      create(:university_calendar_event,
             category: "academic",
             summary: "Classes Begin",
             start_time: Time.zone.local(2024, 8, 26, 0, 0, 0),
             end_time: Time.zone.local(2024, 8, 26, 23, 59, 59))

      # Holiday outside range
      create(:university_calendar_event,
             category: "holiday",
             summary: "Christmas",
             start_time: Time.zone.local(2024, 12, 25, 0, 0, 0),
             end_time: Time.zone.local(2024, 12, 25, 23, 59, 59))
    end

    it "returns only holidays within the meeting time date range" do
      result = instance.holidays_for_meeting_time(meeting_time)

      expect(result.size).to eq(1)
      expect(result.first.summary).to eq("Labor Day")
    end

    it "caches results for the same date range" do
      # First call
      result1 = instance.holidays_for_meeting_time(meeting_time)

      # Create another holiday (shouldn't affect cached result)
      create(:university_calendar_event,
             category: "holiday",
             summary: "Extra Holiday",
             start_time: Time.zone.local(2024, 10, 14, 0, 0, 0),
             end_time: Time.zone.local(2024, 10, 14, 23, 59, 59))

      # Second call should return cached result
      result2 = instance.holidays_for_meeting_time(meeting_time)

      expect(result1).to eq(result2)
      expect(result2.size).to eq(1)
    end
  end

  describe "#format_exdate" do
    let(:date) { Date.new(2024, 11, 28) }
    let(:start_time) { Time.zone.local(2024, 8, 26, 10, 30, 0) }

    it "formats the EXDATE with timezone and correct time" do
      result = instance.format_exdate(date, start_time)

      timezone = Time.zone.tzinfo.name
      expect(result).to eq("EXDATE;TZID=#{timezone}:20241128T103000")
    end
  end

  describe "all-day event handling (12:01pm-11:59pm)" do
    let(:user) { create(:user) }
    let(:term) { create(:term, year: 2024, season: :fall) }
    let(:course) { create(:course, term: term, title: "All Day Workshop") }
    let!(:enrollment) { create(:enrollment, user: user, course: course, term: term) }
    let!(:all_day_meeting_time) do
      create(:meeting_time,
             course: course,
             day_of_week: :monday,
             begin_time: 1201,
             end_time: 2359,
             start_date: Date.new(2024, 8, 26),
             end_date: Date.new(2024, 12, 13))
    end
    let!(:regular_meeting_time) do
      create(:meeting_time,
             course: course,
             day_of_week: :wednesday,
             begin_time: 900,
             end_time: 1050,
             start_date: Date.new(2024, 8, 28),
             end_date: Date.new(2024, 12, 11))
    end

    it "sets all_day: true for meeting times spanning 12:01pm-11:59pm" do
      expect(all_day_meeting_time.all_day?).to be true
    end

    it "sets all_day: false for regular timed meeting times" do
      expect(regular_meeting_time.all_day?).to be false
    end

    describe "event hash generation" do
      let(:google_calendar_service) { instance_double(GoogleCalendarService) }

      before do
        allow(GoogleCalendarService).to receive(:new).and_return(google_calendar_service)
        allow(google_calendar_service).to receive(:update_calendar_events) do |events, **_opts|
          @captured_events = events
          { created: events.size, updated: 0, skipped: 0 }
        end
        user.update_columns(calendar_needs_sync: true)
      end

      it "passes all_day: true to GoogleCalendarService for all-day meeting times" do
        user.sync_course_schedule

        all_day_event = @captured_events.find { |e| e[:meeting_time_id] == all_day_meeting_time.id }
        expect(all_day_event).to be_present
        expect(all_day_event[:all_day]).to be true
      end

      it "passes all_day: false to GoogleCalendarService for regular meeting times" do
        user.sync_course_schedule

        regular_event = @captured_events.find { |e| e[:meeting_time_id] == regular_meeting_time.id }
        expect(regular_event).to be_present
        expect(regular_event[:all_day]).to be false
      end
    end
  end
end
