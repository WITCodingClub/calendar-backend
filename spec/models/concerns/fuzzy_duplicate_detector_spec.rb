# frozen_string_literal: true

require "rails_helper"

RSpec.describe FuzzyDuplicateDetector do
  let(:term) { create(:term, year: 2026, season: :spring) }

  describe ".similarity" do
    it "returns 1.0 for identical strings" do
      expect(UniversityCalendarEvent.similarity("Test Event", "Test Event")).to eq(1.0)
    end

    it "returns 1.0 for strings that differ only in case" do
      expect(UniversityCalendarEvent.similarity("Test Event", "test event")).to eq(1.0)
    end

    it "returns 1.0 for strings that differ only in whitespace" do
      expect(UniversityCalendarEvent.similarity("Test Event", "  Test Event  ")).to eq(1.0)
    end

    it "returns high similarity for very similar strings" do
      similarity = UniversityCalendarEvent.similarity(
        "Wellbeing Day - No Classes",
        "Campus Wellbeing Day"
      )
      expect(similarity).to be > 0.4 # Token-based matching gives ~42% for these
    end

    it "returns low similarity for very different strings" do
      similarity = UniversityCalendarEvent.similarity(
        "Wellbeing Day",
        "Math Exam"
      )
      expect(similarity).to be < 0.3
    end

    it "returns 0.0 for nil strings" do
      expect(UniversityCalendarEvent.similarity(nil, "Test")).to eq(0.0)
      expect(UniversityCalendarEvent.similarity("Test", nil)).to eq(0.0)
    end
  end

  describe ".levenshtein_distance" do
    it "returns 0 for identical strings" do
      expect(UniversityCalendarEvent.levenshtein_distance("test", "test")).to eq(0)
    end

    it "returns string length for completely different strings" do
      expect(UniversityCalendarEvent.levenshtein_distance("abc", "def")).to eq(3)
    end

    it "calculates correct distance for one character difference" do
      expect(UniversityCalendarEvent.levenshtein_distance("test", "text")).to eq(1)
    end

    it "handles empty strings" do
      expect(UniversityCalendarEvent.levenshtein_distance("", "test")).to eq(4)
      expect(UniversityCalendarEvent.levenshtein_distance("test", "")).to eq(4)
    end
  end

  describe ".find_fuzzy_duplicates" do
    let!(:event1) do
      create(:university_calendar_event,
             summary: "Wellbeing Day - No Classes",
             start_time: Time.zone.parse("2026-02-10 00:00"),
             end_time: Time.zone.parse("2026-02-10 23:59:59"),
             category: "holiday",
             organization: "Registrar's Office",
             term: term)
    end

    let!(:event2) do
      create(:university_calendar_event,
             summary: "Campus Wellbeing Day",
             start_time: Time.zone.parse("2026-02-10 00:00"),
             end_time: Time.zone.parse("2026-02-10 23:59:59"),
             category: "holiday",
             organization: "Center for Wellness",
             term: term)
    end

    let!(:different_event) do
      create(:university_calendar_event,
             summary: "Math Exam",
             start_time: Time.zone.parse("2026-02-10 10:00"),
             end_time: Time.zone.parse("2026-02-10 12:00"),
             category: "finals",
             term: term)
    end

    it "finds fuzzy duplicates with similar titles on the same day" do
      duplicates = UniversityCalendarEvent.find_fuzzy_duplicates(
        summary: "Wellbeing Day - No Classes",
        start_time: event1.start_time,
        end_time: event1.end_time,
        category: "holiday",
        exclude_uid: event1.ics_uid
      )

      expect(duplicates).to include(event2)
      expect(duplicates).not_to include(event1)
      expect(duplicates).not_to include(different_event)
    end

    it "does not find events with different categories" do
      duplicates = UniversityCalendarEvent.find_fuzzy_duplicates(
        summary: "Math Exam",
        start_time: different_event.start_time,
        end_time: different_event.end_time,
        category: "holiday", # Wrong category
        exclude_uid: different_event.ics_uid
      )

      expect(duplicates).to be_empty
    end

    it "does not find events on different dates" do
      duplicates = UniversityCalendarEvent.find_fuzzy_duplicates(
        summary: "Wellbeing Day",
        start_time: Time.zone.parse("2026-02-11 00:00"),
        end_time: Time.zone.parse("2026-02-11 23:59:59"),
        category: "holiday",
        exclude_uid: nil
      )

      expect(duplicates).to be_empty
    end

    it "returns empty array when no fuzzy matches exist" do
      duplicates = UniversityCalendarEvent.find_fuzzy_duplicates(
        summary: "Completely Different Event Name",
        start_time: event1.start_time,
        end_time: event1.end_time,
        category: "holiday",
        exclude_uid: nil
      )

      expect(duplicates).to be_empty
    end
  end

  describe ".organization_priority" do
    it "returns high priority for Registrar's Office" do
      expect(UniversityCalendarEvent.organization_priority("Registrar's Office")).to eq(100)
    end

    it "returns medium priority for Academic Affairs" do
      expect(UniversityCalendarEvent.organization_priority("Academic Affairs")).to eq(90)
    end

    it "returns low priority for Center for Wellness" do
      expect(UniversityCalendarEvent.organization_priority("Center for Wellness")).to eq(70)
    end

    it "returns 0 for unknown organizations" do
      expect(UniversityCalendarEvent.organization_priority("Unknown Org")).to eq(0)
    end

    it "returns 0 for nil organization" do
      expect(UniversityCalendarEvent.organization_priority(nil)).to eq(0)
    end
  end

  describe ".preferred_event" do
    let(:base_time) { Time.zone.parse("2026-02-10 00:00") }

    let!(:registrar_event) do
      create(:university_calendar_event,
             summary: "Wellbeing Day",
             start_time: base_time,
             end_time: base_time + 1.day,
             organization: "Registrar's Office",
             last_fetched_at: 1.hour.ago,
             created_at: 2.days.ago,
             term: term)
    end

    let!(:wellness_event) do
      create(:university_calendar_event,
             summary: "Campus Wellbeing Day",
             start_time: base_time,
             end_time: base_time + 1.day,
             organization: "Center for Wellness",
             last_fetched_at: 30.minutes.ago,
             created_at: 1.day.ago,
             term: term)
    end

    let!(:no_org_event) do
      create(:university_calendar_event,
             summary: "Wellbeing Day Event",
             start_time: base_time,
             end_time: base_time + 1.day,
             organization: nil,
             last_fetched_at: 10.minutes.ago,
             created_at: 3.days.ago,
             term: term)
    end

    it "prefers Registrar's Office over other organizations" do
      preferred = UniversityCalendarEvent.preferred_event([wellness_event, registrar_event, no_org_event])
      expect(preferred).to eq(registrar_event)
    end

    it "prefers most recently fetched when organizations have same priority" do
      event1 = create(:university_calendar_event,
                      organization: "Unknown Org 1",
                      last_fetched_at: 1.hour.ago,
                      created_at: 2.days.ago,
                      term: term)
      event2 = create(:university_calendar_event,
                      organization: "Unknown Org 2",
                      last_fetched_at: 10.minutes.ago,
                      created_at: 1.day.ago,
                      term: term)

      preferred = UniversityCalendarEvent.preferred_event([event1, event2])
      expect(preferred).to eq(event2)
    end

    it "prefers oldest created when last_fetched_at is the same" do
      same_fetch_time = 1.hour.ago
      event1 = create(:university_calendar_event,
                      organization: nil,
                      last_fetched_at: same_fetch_time,
                      created_at: 2.days.ago,
                      term: term)
      event2 = create(:university_calendar_event,
                      organization: nil,
                      last_fetched_at: same_fetch_time,
                      created_at: 1.day.ago,
                      term: term)

      preferred = UniversityCalendarEvent.preferred_event([event1, event2])
      expect(preferred).to eq(event1)
    end
  end

  describe "#fuzzy_duplicate_of?" do
    let!(:event1) do
      create(:university_calendar_event,
             summary: "Wellbeing Day - No Classes",
             start_time: Time.zone.parse("2026-02-10 00:00"),
             end_time: Time.zone.parse("2026-02-10 23:59:59"),
             category: "holiday",
             term: term)
    end

    let!(:event2) do
      create(:university_calendar_event,
             summary: "Campus Wellbeing Day",
             start_time: Time.zone.parse("2026-02-10 00:00"),
             end_time: Time.zone.parse("2026-02-10 23:59:59"),
             category: "holiday",
             term: term)
    end

    it "returns true for similar events on the same day" do
      expect(event1.fuzzy_duplicate_of?(event2)).to be true
      expect(event2.fuzzy_duplicate_of?(event1)).to be true
    end

    it "returns false for the same event" do
      expect(event1.fuzzy_duplicate_of?(event1)).to be false
    end

    it "returns false for events with different categories" do
      different_category = create(:university_calendar_event,
                                  summary: "Wellbeing Day",
                                  start_time: event1.start_time,
                                  end_time: event1.end_time,
                                  category: "campus_event",
                                  term: term)

      expect(event1.fuzzy_duplicate_of?(different_category)).to be false
    end

    it "returns false for events on different days" do
      different_day = create(:university_calendar_event,
                             summary: "Wellbeing Day",
                             start_time: Time.zone.parse("2026-02-11 00:00"),
                             end_time: Time.zone.parse("2026-02-11 23:59:59"),
                             category: "holiday",
                             term: term)

      expect(event1.fuzzy_duplicate_of?(different_day)).to be false
    end

    it "returns false for events with very different titles" do
      different_title = create(:university_calendar_event,
                               summary: "Math Exam",
                               start_time: event1.start_time,
                               end_time: event1.end_time,
                               category: "holiday",
                               term: term)

      expect(event1.fuzzy_duplicate_of?(different_title)).to be false
    end
  end
end
