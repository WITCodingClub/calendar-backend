# frozen_string_literal: true

# == Schema Information
#
# Table name: university_calendar_events
# Database name: primary
#
#  id              :bigint           not null, primary key
#  academic_term   :string
#  all_day         :boolean          default(FALSE), not null
#  category        :string
#  description     :text
#  end_time        :datetime         not null
#  event_type_raw  :string
#  ics_uid         :string           not null
#  last_fetched_at :datetime
#  location        :string
#  organization    :string
#  recurrence      :text
#  source_url      :string
#  start_time      :datetime         not null
#  summary         :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  term_id         :bigint
#
# Indexes
#
#  index_university_calendar_events_on_academic_term            (academic_term)
#  index_university_calendar_events_on_category                 (category)
#  index_university_calendar_events_on_ics_uid                  (ics_uid) UNIQUE
#  index_university_calendar_events_on_start_time               (start_time)
#  index_university_calendar_events_on_start_time_and_end_time  (start_time,end_time)
#  index_university_calendar_events_on_term_id                  (term_id)
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#
require "rails_helper"

RSpec.describe UniversityCalendarEvent do
  describe "associations" do
    it { is_expected.to belong_to(:term).optional }
    it { is_expected.to have_many(:google_calendar_events).dependent(:nullify) }
  end

  describe "validations" do
    subject { build(:university_calendar_event) }

    it { is_expected.to validate_presence_of(:ics_uid) }
    it { is_expected.to validate_uniqueness_of(:ics_uid) }
    it { is_expected.to validate_presence_of(:summary) }
    it { is_expected.to validate_presence_of(:start_time) }
    it { is_expected.to validate_presence_of(:end_time) }

    it "validates category inclusion" do
      event = build(:university_calendar_event, category: "invalid_category")
      expect(event).not_to be_valid
      expect(event.errors[:category]).to include("is not included in the list")
    end

    it "allows valid categories" do
      UniversityCalendarEvent::CATEGORIES.each do |category|
        event = build(:university_calendar_event, category: category)
        expect(event).to be_valid
      end
    end

    it "allows blank category" do
      event = build(:university_calendar_event, category: nil)
      expect(event).to be_valid
    end
  end

  describe "scopes" do
    describe ".upcoming" do
      it "returns events starting today or later" do
        past_event = create(:university_calendar_event, :past)
        future_event = create(:university_calendar_event, start_time: 1.day.from_now)
        today_event = create(:university_calendar_event, start_time: Time.current)

        expect(described_class.upcoming).to include(future_event, today_event)
        expect(described_class.upcoming).not_to include(past_event)
      end
    end

    describe ".past" do
      it "returns events that have already started" do
        past_event = create(:university_calendar_event, :past)
        future_event = create(:university_calendar_event, start_time: 1.day.from_now)

        expect(described_class.past).to include(past_event)
        expect(described_class.past).not_to include(future_event)
      end
    end

    describe ".holidays" do
      it "returns only holiday events" do
        holiday = create(:university_calendar_event, :holiday)
        term_dates = create(:university_calendar_event, :term_dates)

        expect(described_class.holidays).to include(holiday)
        expect(described_class.holidays).not_to include(term_dates)
      end
    end

    describe ".term_dates" do
      it "returns only term_dates events" do
        holiday = create(:university_calendar_event, :holiday)
        term_dates = create(:university_calendar_event, :term_dates)

        expect(described_class.term_dates).to include(term_dates)
        expect(described_class.term_dates).not_to include(holiday)
      end
    end

    describe ".registration" do
      it "returns only registration events" do
        registration = create(:university_calendar_event, :registration)
        holiday = create(:university_calendar_event, :holiday)

        expect(described_class.registration).to include(registration)
        expect(described_class.registration).not_to include(holiday)
      end
    end

    describe ".finals" do
      it "returns only finals events" do
        finals = create(:university_calendar_event, :finals)
        holiday = create(:university_calendar_event, :holiday)

        expect(described_class.finals).to include(finals)
        expect(described_class.finals).not_to include(holiday)
      end
    end

    describe ".graduation" do
      it "returns only graduation events" do
        graduation = create(:university_calendar_event, :graduation)
        holiday = create(:university_calendar_event, :holiday)

        expect(described_class.graduation).to include(graduation)
        expect(described_class.graduation).not_to include(holiday)
      end
    end

    describe ".deadlines" do
      it "returns only deadline events" do
        deadline = create(:university_calendar_event, :deadline)
        holiday = create(:university_calendar_event, :holiday)

        expect(described_class.deadlines).to include(deadline)
        expect(described_class.deadlines).not_to include(holiday)
      end
    end

    describe ".academic" do
      it "returns only academic events" do
        academic = create(:university_calendar_event, :academic)
        holiday = create(:university_calendar_event, :holiday)

        expect(described_class.academic).to include(academic)
        expect(described_class.academic).not_to include(holiday)
      end
    end

    describe ".in_date_range" do
      it "returns events within the date range" do
        in_range = create(:university_calendar_event,
                          start_time: Date.new(2025, 3, 15).beginning_of_day)
        out_of_range = create(:university_calendar_event,
                              start_time: Date.new(2025, 5, 1).beginning_of_day)

        result = described_class.in_date_range(Date.new(2025, 3, 1), Date.new(2025, 3, 31))

        expect(result).to include(in_range)
        expect(result).not_to include(out_of_range)
      end
    end

    describe ".by_categories" do
      it "returns events matching specified categories" do
        holiday = create(:university_calendar_event, :holiday)
        term_dates = create(:university_calendar_event, :term_dates)
        campus = create(:university_calendar_event, :campus_event)

        result = described_class.by_categories(%w[holiday term_dates])

        expect(result).to include(holiday, term_dates)
        expect(result).not_to include(campus)
      end
    end

    describe ".with_location" do
      it "returns events that have a location" do
        with_location = create(:university_calendar_event, location: "Room 101")
        without_location = create(:university_calendar_event, location: nil)
        empty_location = create(:university_calendar_event, location: "")

        result = described_class.with_location

        expect(result).to include(with_location)
        expect(result).not_to include(without_location, empty_location)
      end
    end

    describe ".without_location" do
      it "returns events that have no location" do
        with_location = create(:university_calendar_event, location: "Room 101")
        without_location = create(:university_calendar_event, location: nil)
        empty_location = create(:university_calendar_event, location: "")

        result = described_class.without_location

        expect(result).to include(without_location, empty_location)
        expect(result).not_to include(with_location)
      end
    end
  end

  describe ".holidays_between" do
    it "returns holidays in the date range ordered by start_time" do
      holiday1 = create(:university_calendar_event, :holiday,
                        start_time: Date.new(2025, 3, 10).beginning_of_day)
      holiday2 = create(:university_calendar_event, :holiday,
                        start_time: Date.new(2025, 3, 20).beginning_of_day)
      holiday3 = create(:university_calendar_event, :holiday,
                        start_time: Date.new(2025, 5, 1).beginning_of_day)
      term_dates = create(:university_calendar_event, :term_dates,
                          start_time: Date.new(2025, 3, 15).beginning_of_day)

      result = described_class.holidays_between(Date.new(2025, 3, 1), Date.new(2025, 3, 31))

      expect(result).to eq([holiday1, holiday2])
      expect(result).not_to include(holiday3, term_dates)
    end
  end

  describe ".infer_category" do
    it "detects holiday events" do
      expect(described_class.infer_category("Winter Break", nil)).to eq("holiday")
      expect(described_class.infer_category("Thanksgiving Holiday", nil)).to eq("holiday")
      expect(described_class.infer_category("Memorial Day - No Classes", nil)).to eq("holiday")
      expect(described_class.infer_category("All Offices Closed", nil)).to eq("holiday")
      expect(described_class.infer_category("Labor Day", nil)).to eq("holiday")
    end

    it "detects term_dates events" do
      expect(described_class.infer_category("Fall 2025 Classes Begin", nil)).to eq("term_dates")
      expect(described_class.infer_category("Classes End", nil)).to eq("term_dates")
      expect(described_class.infer_category("First Day of Classes", nil)).to eq("term_dates")
      expect(described_class.infer_category("Last Day of Classes", nil)).to eq("term_dates")
    end

    it "detects finals events" do
      expect(described_class.infer_category("Final Exams Week", nil)).to eq("finals")
      expect(described_class.infer_category("Finals Week", nil)).to eq("finals")
      expect(described_class.infer_category("Examination Period", nil)).to eq("finals")
    end

    it "detects registration events" do
      expect(described_class.infer_category("Registration Opens", nil)).to eq("registration")
      expect(described_class.infer_category("Enrollment Period", nil)).to eq("registration")
      expect(described_class.infer_category("Add/Drop Period", nil)).to eq("registration")
    end

    it "detects deadline events" do
      expect(described_class.infer_category("Withdrawal Deadline", nil)).to eq("deadline")
      expect(described_class.infer_category("Last Day to Drop", nil)).to eq("deadline")
      expect(described_class.infer_category("Tuition Due", nil)).to eq("deadline")
    end

    it "detects graduation events" do
      expect(described_class.infer_category("Commencement Ceremony", nil)).to eq("graduation")
      expect(described_class.infer_category("Graduation 2025", nil)).to eq("graduation")
      expect(described_class.infer_category("Convocation", nil)).to eq("graduation")
    end

    it "detects meeting events" do
      expect(described_class.infer_category("Board Meeting", "Meeting")).to eq("meeting")
    end

    it "detects exhibit events" do
      expect(described_class.infer_category("Art Show", "Exhibit")).to eq("exhibit")
      expect(described_class.infer_category("Student Showcase", "Showcase")).to eq("exhibit")
    end

    it "detects announcement events" do
      expect(described_class.infer_category("Important Notice", "Announcement")).to eq("announcement")
    end

    it "detects academic events from calendar announcement type" do
      expect(described_class.infer_category("Some Academic Event", "Calendar Announcement")).to eq("academic")
    end

    it "defaults to campus_event for unknown types" do
      expect(described_class.infer_category("Random Event", nil)).to eq("campus_event")
      expect(described_class.infer_category("Something Happening", "Other")).to eq("campus_event")
    end
  end

  describe ".detect_term_dates" do
    it "finds classes begin and end events for a term" do
      create(:university_calendar_event, :term_dates,
             summary: "Fall 2025 Classes Begin",
             academic_term: "Fall",
             start_time: Date.new(2025, 8, 25).beginning_of_day)
      create(:university_calendar_event, :finals,
             summary: "Fall 2025 Final Exams",
             academic_term: "Fall",
             start_time: Date.new(2025, 12, 15).beginning_of_day,
             end_time: Date.new(2025, 12, 19).end_of_day)

      result = described_class.detect_term_dates(2025, :fall)

      expect(result[:start_date]).to eq(Date.new(2025, 8, 25))
      expect(result[:end_date]).to eq(Date.new(2025, 12, 19))
    end

    it "returns nil dates when no matching events found" do
      result = described_class.detect_term_dates(2030, :spring)

      expect(result[:start_date]).to be_nil
      expect(result[:end_date]).to be_nil
    end
  end

  describe "#term_boundary_event?" do
    it "returns true for classes begin events" do
      event = build(:university_calendar_event, :classes_begin)
      expect(event.term_boundary_event?).to be true
    end

    it "returns true for classes end events" do
      event = build(:university_calendar_event, :classes_end)
      expect(event.term_boundary_event?).to be true
    end

    it "returns true for all term_dates category events" do
      event = build(:university_calendar_event, :term_dates)
      expect(event.term_boundary_event?).to be true
    end

    it "returns false for non-term_dates events" do
      event = build(:university_calendar_event, :holiday)
      expect(event.term_boundary_event?).to be false
    end

    it "returns false for registration events" do
      event = build(:university_calendar_event, :registration)
      expect(event.term_boundary_event?).to be false
    end
  end

  describe "#excludes_classes?" do
    it "returns true for holiday events" do
      event = build(:university_calendar_event, :holiday)
      expect(event.excludes_classes?).to be true
    end

    it "returns false for non-holiday events" do
      event = build(:university_calendar_event, :term_dates)
      expect(event.excludes_classes?).to be false
    end
  end

  describe "#formatted_date" do
    it "formats all-day events without time" do
      event = build(:university_calendar_event, all_day: true,
                                                start_time: Date.new(2025, 3, 15).beginning_of_day)
      expect(event.formatted_date).to eq("March 15, 2025")
    end

    it "formats timed events with time" do
      event = build(:university_calendar_event, all_day: false,
                                                start_time: Time.zone.local(2025, 3, 15, 14, 30))
      expect(event.formatted_date).to eq("March 15, 2025 at 2:30 PM")
    end
  end

  describe "#duration_hours" do
    it "returns nil for all-day events" do
      event = build(:university_calendar_event, all_day: true)
      expect(event.duration_hours).to be_nil
    end

    it "calculates duration for timed events" do
      event = build(:university_calendar_event, all_day: false,
                                                start_time: Time.zone.local(2025, 3, 15, 14, 0),
                                                end_time: Time.zone.local(2025, 3, 15, 16, 30))
      expect(event.duration_hours).to eq(2.5)
    end
  end

  describe "recurrence serialization" do
    it "stores array as JSON" do
      event = create(:university_calendar_event, recurrence: ["RRULE:FREQ=WEEKLY;COUNT=10"])
      event.reload
      expect(event.recurrence).to eq(["RRULE:FREQ=WEEKLY;COUNT=10"])
    end

    it "handles nil" do
      event = create(:university_calendar_event, recurrence: nil)
      event.reload
      expect(event.recurrence).to be_nil
    end
  end

  describe "#formatted_holiday_summary" do
    it "adds emoji prefix and 'No Classes' suffix for regular holidays" do
      event = build(:university_calendar_event, :holiday, summary: "Labor Day")
      expect(event.formatted_holiday_summary).to eq("🏫 Labor Day - No Classes")
    end

    it "adds only emoji prefix when summary already contains 'No Classes'" do
      event = build(:university_calendar_event, :holiday, summary: "Thanksgiving Break - No Classes")
      expect(event.formatted_holiday_summary).to eq("🏫 Thanksgiving Break - No Classes")
    end

    it "handles 'no class' (singular) in summary" do
      event = build(:university_calendar_event, :holiday, summary: "Holiday - No Class")
      expect(event.formatted_holiday_summary).to eq("🏫 Holiday - No Class")
    end

    it "uses word boundaries to avoid false positives like 'classical'" do
      event = build(:university_calendar_event, :holiday, summary: "Classical Music Day")
      expect(event.formatted_holiday_summary).to eq("🏫 Classical Music Day - No Classes")
    end

    it "is case insensitive when checking for 'no classes'" do
      event = build(:university_calendar_event, :holiday, summary: "Holiday - NO CLASSES")
      expect(event.formatted_holiday_summary).to eq("🏫 Holiday - NO CLASSES")
    end
  end
end
