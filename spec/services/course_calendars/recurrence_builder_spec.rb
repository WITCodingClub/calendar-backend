# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseCalendars::RecurrenceBuilder do
  subject(:builder) { described_class.new(user) }

  let(:user)   { create(:user) }
  let(:term)   { create(:term) }
  # The factory course runs from Tuesday 2026-09-08 to Tuesday 2026-12-15.
  let(:course) { create(:course, term: term) }
  let(:meeting_time) { create(:course_meeting_time, course: course, day_of_week: :monday, begin_time: 900) }

  def holiday(start_time, end_time = start_time + 1.hour, category: "holiday")
    create(:university_calendar_event, category: category, start_time: start_time, end_time: end_time)
  end

  describe "#find_first_meeting_date" do
    it "returns the first date on the meeting day" do
      expect(builder.find_first_meeting_date(meeting_time)).to eq(Date.new(2026, 9, 14))
    end

    it "returns the start date when the class meets on that day" do
      meeting_time.update!(day_of_week: :tuesday)

      expect(builder.find_first_meeting_date(meeting_time)).to eq(Date.new(2026, 9, 8))
    end
  end

  describe "#parse_time" do
    it "turns an integer time into a local time" do
      expect(builder.parse_time(Date.new(2026, 9, 14), 1330)).to eq(Time.zone.local(2026, 9, 14, 13, 30))
    end

    it "returns nil without a date" do
      expect(builder.parse_time(nil, 900)).to be_nil
    end
  end

  describe "#build_recurrence_rule" do
    it "repeats weekly until the end of the last day in local time" do
      rule = builder.build_recurrence_rule(meeting_time)

      expect(rule).to start_with("RRULE:FREQ=WEEKLY")
      expect(rule).to include("BYDAY=MO", "UNTIL=20261216T045959Z")
    end

    it "stops the day before the course's final exam" do
      create(:final_exam, course: course, term: term, exam_date: Date.new(2026, 12, 10))

      expect(builder.build_recurrence_rule(meeting_time)).to include("UNTIL=20261210T045959Z")
    end

    it "stops the day before the term's first final when the course has none" do
      create(:final_exam, term: term, exam_date: Date.new(2026, 12, 12))

      expect(builder.build_recurrence_rule(meeting_time)).to include("UNTIL=20261212T045959Z")
    end

    it "ignores an early final that few sections of the term hold when the course has none" do
      create(:final_exam, term: term, exam_date: Date.new(2026, 11, 19))
      create_list(:final_exam, 10, term: term, exam_date: Date.new(2026, 12, 10))

      expect(builder.build_recurrence_rule(meeting_time)).to include("UNTIL=20261210T045959Z")
    end

    it "stops the day before Study Day" do
      create(:university_calendar_event, term: term, category: "finals", summary: "Study Day",
                                         start_time: Time.zone.local(2026, 12, 8, 0, 0), end_time: Time.zone.local(2026, 12, 8, 23, 59))

      expect(builder.build_recurrence_rule(meeting_time)).to include("UNTIL=20261208T045959Z")
    end

    it "ignores a finals announcement that is not a no-class day" do
      create(:university_calendar_event, term: term, category: "finals", summary: "Final Exam Schedule Online",
                                         start_time: Time.zone.local(2026, 11, 1, 9, 0), end_time: Time.zone.local(2026, 11, 1, 10, 0))

      expect(builder.build_recurrence_rule(meeting_time)).to include("UNTIL=20261216T045959Z")
    end
  end

  describe "#effective_end_date" do
    it "returns the stored end date when the term has no finals" do
      expect(builder.effective_end_date(meeting_time)).to eq(Date.new(2026, 12, 15))
    end

    it "returns the day before the course's final exam" do
      create(:final_exam, course: course, term: term, exam_date: Date.new(2026, 12, 10))

      expect(builder.effective_end_date(meeting_time)).to eq(Date.new(2026, 12, 9))
    end

    it "returns the day before the term's finals week when the course has no final" do
      create(:final_exam, term: term, exam_date: Date.new(2026, 12, 12))

      expect(builder.effective_end_date(meeting_time)).to eq(Date.new(2026, 12, 11))
    end

    it "returns the day before Study Day and keeps the stored end date" do
      create(:university_calendar_event, term: term, category: "finals", summary: "Study Day",
                                         start_time: Time.zone.local(2026, 12, 8, 0, 0), end_time: Time.zone.local(2026, 12, 8, 23, 59))

      expect(builder.effective_end_date(meeting_time)).to eq(Date.new(2026, 12, 7))
      expect(meeting_time.reload.end_date.to_date).to eq(Date.new(2026, 12, 15))
    end
  end

  describe "#excluded_dates" do
    it "returns a holiday on the meeting day" do
      holiday(Time.zone.local(2026, 10, 12, 0, 0))

      expect(builder.excluded_dates(meeting_time)).to eq([ Date.new(2026, 10, 12) ])
    end

    it "returns the meeting day inside a holiday of several days" do
      holiday(Time.zone.local(2026, 11, 21, 0, 0), Time.zone.local(2026, 11, 25, 23, 0))

      expect(builder.excluded_dates(meeting_time)).to eq([ Date.new(2026, 11, 23) ])
    end

    it "leaves out a holiday on another day" do
      holiday(Time.zone.local(2026, 10, 13, 0, 0))

      expect(builder.excluded_dates(meeting_time)).to eq([])
    end

    it "leaves out finals days after the effective end date" do
      create(:university_calendar_event, term: term, category: "finals", summary: "Study Day",
                                         start_time: Time.zone.local(2026, 12, 8, 0, 0), end_time: Time.zone.local(2026, 12, 8, 23, 59))
      create(:university_calendar_event, term: term, category: "finals", summary: "Final Exam Period",
                                         start_time: Time.zone.local(2026, 12, 9, 0, 0), end_time: Time.zone.local(2026, 12, 15, 23, 59))

      expect(builder.excluded_dates(meeting_time)).to eq([])
    end
  end

  describe "#preload_final_exam_dates!" do
    it "loads the final exam dates of all courses in one query" do
      other_course = create(:course, term: term)
      create(:final_exam, course: course, term: term, exam_date: Date.new(2026, 12, 10))

      builder.preload_final_exam_dates!([ course.id, other_course.id ])
      allow(FinalExam).to receive(:where).and_call_original

      expect(builder.final_exam_date_for_course(course.id)).to eq(Date.new(2026, 12, 10))
      expect(builder.final_exam_date_for_course(other_course.id)).to be_nil
      expect(FinalExam).not_to have_received(:where)
    end
  end

  describe ".preloaded" do
    it "loads the holidays, final exam dates, and finals dates, so the lookups send no query" do
      create(:enrollment, user: user, course: course)
      meeting_time
      holiday(Time.zone.local(2026, 10, 12, 0, 0))
      create(:final_exam, term: term, exam_date: Date.new(2026, 12, 12))
      create(:university_calendar_event, term: term, category: "finals", summary: "Study Day",
                                         start_time: Time.zone.local(2026, 12, 8, 0, 0), end_time: Time.zone.local(2026, 12, 8, 23, 59))

      preloaded = described_class.preloaded(user, [ course ])
      queries = count_queries do
        expect(preloaded.effective_end_date(meeting_time)).to eq(Date.new(2026, 12, 7))
        expect(preloaded.excluded_dates(meeting_time)).to eq([ Date.new(2026, 10, 12) ])
      end

      expect(queries).to eq(0)
    end
  end

  describe "#final_exam_date_for_course" do
    it "sends the query only once for each course" do
      create(:final_exam, course: course, term: term, exam_date: Date.new(2026, 12, 10))
      allow(FinalExam).to receive(:where).and_call_original

      2.times { expect(builder.final_exam_date_for_course(course.id)).to eq(Date.new(2026, 12, 10)) }

      expect(FinalExam).to have_received(:where).once
    end
  end

  describe "#build_recurrence_with_exclusions" do
    let(:start_time) { Time.zone.local(2026, 9, 14, 9, 0) }

    it "returns nil without a rule" do
      expect(builder.build_recurrence_with_exclusions(meeting_time, nil, start_time)).to be_nil
    end

    it "adds an EXDATE for a holiday on the meeting day" do
      holiday(Time.zone.local(2026, 10, 12, 0, 0))

      expect(builder.build_recurrence_with_exclusions(meeting_time, "RRULE:X", start_time))
        .to eq([ "RRULE:X", "EXDATE;TZID=America/New_York:20261012T090000" ])
    end

    it "adds an EXDATE for the meeting day inside a holiday of several days" do
      holiday(Time.zone.local(2026, 11, 21, 0, 0), Time.zone.local(2026, 11, 25, 23, 0))

      expect(builder.build_recurrence_with_exclusions(meeting_time, "RRULE:X", start_time))
        .to eq([ "RRULE:X", "EXDATE;TZID=America/New_York:20261123T090000" ])
    end

    it "adds no EXDATE for a holiday on another day" do
      holiday(Time.zone.local(2026, 10, 13, 0, 0))

      expect(builder.build_recurrence_with_exclusions(meeting_time, "RRULE:X", start_time)).to eq([ "RRULE:X" ])
    end
  end

  describe "#preload_holidays_for_user!" do
    it "lets holidays_for_meeting_time read the preloaded holidays without a query" do
      create(:enrollment, user: user, course: course)
      meeting_time
      day_off = holiday(Time.zone.local(2026, 10, 12, 0, 0))
      holiday(Time.zone.local(2027, 3, 1, 0, 0))

      builder.preload_holidays_for_user!
      allow(UniversityCalendarEvent).to receive(:no_class_spans_between).and_call_original

      expect(builder.holidays_for_meeting_time(meeting_time).map(&:start_time)).to eq([ day_off.start_time ])
      expect(UniversityCalendarEvent).not_to have_received(:no_class_spans_between)
    end

    it "preloads no holidays for a user without meeting times" do
      holiday(Time.zone.local(2026, 10, 12, 0, 0))

      expect(builder.preload_holidays_for_user!).to eq([])
    end
  end

  describe "#holidays_for_meeting_time" do
    it "queries the holidays of the date range without a preload" do
      day_off = holiday(Time.zone.local(2026, 10, 12, 0, 0))

      expect(builder.holidays_for_meeting_time(meeting_time).map(&:start_time)).to eq([ day_off.start_time ])
    end
  end
end
