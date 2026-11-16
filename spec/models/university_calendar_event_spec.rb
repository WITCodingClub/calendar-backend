# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: university_calendar_events
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
#  summary         :text             not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  term_id         :bigint
#
# Indexes
#
#  index_university_calendar_events_on_academic_term            (academic_term)
#  index_university_calendar_events_on_category                 (category)
#  index_university_calendar_events_on_ics_uid                  (ics_uid) UNIQUE
#  index_university_calendar_events_on_start_time_and_end_time  (start_time,end_time)
#  index_university_calendar_events_on_term_id                  (term_id)
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#
RSpec.describe UniversityCalendarEvent, type: :model do
  subject { create(:university_calendar_event) }

  it { is_expected.to belong_to(:term).optional }
  it { is_expected.to have_many(:calendar_events).dependent(:nullify) }

  it { is_expected.to validate_presence_of(:ics_uid) }
  it { is_expected.to validate_uniqueness_of(:ics_uid) }
  it { is_expected.to validate_presence_of(:summary) }
  it { is_expected.to validate_presence_of(:start_time) }
  it { is_expected.to validate_presence_of(:end_time) }
  it { is_expected.to validate_inclusion_of(:category).in_array(UniversityCalendarEvent::CATEGORIES).allow_blank }

  describe "SYNCABLE_CATEGORIES" do
    it "is a subset of the stored categories" do
      expect(UniversityCalendarEvent::CATEGORIES).to include(*UniversityCalendarEvent::SYNCABLE_CATEGORIES)
    end

    it "leaves out the cluttered feed categories" do
      expect(UniversityCalendarEvent::SYNCABLE_CATEGORIES).not_to include("campus_event", "meeting", "exhibit", "announcement", "other")
    end
  end

  describe ".category_description" do
    it "gives every syncable category its own description" do
      descriptions = UniversityCalendarEvent::SYNCABLE_CATEGORIES.map { |category| described_class.category_description(category) }

      expect(descriptions).to all(be_present)
      expect(descriptions).to eq(descriptions.uniq)
    end

    it "returns the description of a known category" do
      expect(described_class.category_description("finals")).to eq("Final exam schedules and exam periods")
    end

    it "falls back for an unknown category" do
      expect(described_class.category_description("parties")).to eq("Other university events")
    end
  end

  describe "scopes" do
    include ActiveSupport::Testing::TimeHelpers

    around { |example| travel_to(Time.zone.local(2026, 10, 9, 12, 0)) { example.run } }

    def event_in(category, **attrs)
      create(:university_calendar_event, category: category, **attrs)
    end

    { holidays: "holiday", finals: "finals" }.each do |scope_name, category|
      it ".#{scope_name} returns only #{category} events" do
        match = event_in(category)
        event_in("other")

        expect(described_class.public_send(scope_name)).to contain_exactly(match)
      end
    end

    it ".upcoming starts at the beginning of today" do
      today  = event_in("holiday", start_time: Time.zone.local(2026, 10, 9, 0, 30), end_time: Time.zone.local(2026, 10, 9, 1, 0))
      future = event_in("holiday", start_time: 2.days.from_now, end_time: 3.days.from_now)
      event_in("holiday", start_time: 1.day.ago, end_time: 1.day.ago + 1.hour)

      expect(described_class.upcoming).to contain_exactly(today, future)
    end

    it ".for_term returns events of one term" do
      term = create(:term)
      match = event_in("holiday", term: term)
      event_in("holiday")

      expect(described_class.for_term(term)).to contain_exactly(match)
    end

    it ".with_location leaves out nil and empty locations" do
      match = event_in("holiday", location: "Beatty Hall")
      event_in("holiday", location: "")
      event_in("holiday", location: nil)

      expect(described_class.with_location).to contain_exactly(match)
    end

    it ".by_categories returns events in any listed category" do
      holiday = event_in("holiday")
      finals = event_in("finals")
      event_in("deadline")

      expect(described_class.by_categories(%w[holiday finals])).to contain_exactly(holiday, finals)
    end

    it ".in_date_range includes the whole first and last day" do
      first_day = event_in("holiday", start_time: Time.zone.local(2026, 11, 2, 0, 5), end_time: Time.zone.local(2026, 11, 2, 1, 0))
      last_day  = event_in("holiday", start_time: Time.zone.local(2026, 11, 4, 23, 50), end_time: Time.zone.local(2026, 11, 5, 0, 30))
      event_in("holiday", start_time: Time.zone.local(2026, 11, 5, 0, 5), end_time: Time.zone.local(2026, 11, 5, 1, 0))

      expect(described_class.in_date_range(Date.new(2026, 11, 2), Date.new(2026, 11, 4))).to contain_exactly(first_day, last_day)
    end

    it ".in_date_range includes an event that started before the range and runs into it" do
      break_week = event_in("holiday", start_time: Time.zone.local(2026, 10, 7), end_time: Time.zone.local(2026, 10, 11, 23, 59))
      event_in("holiday", start_time: Time.zone.local(2026, 10, 1), end_time: Time.zone.local(2026, 10, 8, 23, 59))
      event_in("holiday", start_time: Time.zone.local(2026, 10, 12), end_time: Time.zone.local(2026, 10, 13))

      expect(described_class.in_date_range(Date.new(2026, 10, 9), Date.new(2026, 10, 9))).to include(break_week)
      expect(described_class.in_date_range(Date.new(2026, 10, 9), Date.new(2026, 10, 9)).count).to eq(1)
    end

    it ".no_class_dates_between lists only the dates of a multi-day break that fall inside the range" do
      event_in("holiday", start_time: Time.zone.local(2026, 10, 7), end_time: Time.zone.local(2026, 10, 11, 23, 59))

      expect(described_class.no_class_dates_between(Date.new(2026, 10, 9), Date.new(2026, 10, 20)))
        .to contain_exactly(Date.new(2026, 10, 9), Date.new(2026, 10, 10), Date.new(2026, 10, 11))
    end

    it ".no_class_spans_between returns holidays, study days and finals only, earliest first" do
      finals = event_in("finals", start_time: Time.zone.local(2026, 11, 12, 9, 0), end_time: Time.zone.local(2026, 11, 12, 10, 0))
      study = event_in("study_day", start_time: Time.zone.local(2026, 11, 11, 9, 0), end_time: Time.zone.local(2026, 11, 11, 10, 0))
      break_week = event_in("holiday", start_time: Time.zone.local(2026, 10, 28), end_time: Time.zone.local(2026, 11, 2, 23, 59))
      event_in("deadline", start_time: Time.zone.local(2026, 11, 13, 9, 0), end_time: Time.zone.local(2026, 11, 13, 10, 0))
      event_in("holiday", start_time: Time.zone.local(2026, 12, 1), end_time: Time.zone.local(2026, 12, 1, 23, 59))

      spans = described_class.no_class_spans_between(Date.new(2026, 11, 1), Date.new(2026, 11, 30))

      expect(spans.map(&:start_time)).to eq([ break_week, study, finals ].map(&:start_time))
    end
  end

  describe ".no_class_spans_between caching" do
    let(:key) { UniversityCalendarEvent::NO_CLASS_SPANS_CACHE_KEY }
    let(:range) { [ Date.new(2026, 11, 1), Date.new(2026, 11, 30) ] }

    around do |example|
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
      Rails.cache = original
    end

    def holiday_on(day)
      create(:university_calendar_event, category: "holiday", start_time: day, end_time: day + 1.hour)
    end

    it "reads the spans from Rails.cache after the first call" do
      holiday_on(Time.zone.local(2026, 11, 10))
      described_class.no_class_spans_between(*range)
      allow(described_class).to receive(:where).and_call_original

      expect(described_class.no_class_spans_between(*range).size).to eq(1)
      expect(described_class).not_to have_received(:where)
    end

    it "clears the cache when an event is created" do
      described_class.no_class_spans_between(*range)
      holiday_on(Time.zone.local(2026, 11, 10))

      expect(Rails.cache.exist?(key)).to be(false)
      expect(described_class.no_class_spans_between(*range).size).to eq(1)
    end

    it "clears the cache when an event changes category" do
      event = holiday_on(Time.zone.local(2026, 11, 10))
      described_class.no_class_spans_between(*range)
      event.update!(category: "deadline")

      expect(described_class.no_class_spans_between(*range)).to be_empty
    end

    it "clears the cache when an event is destroyed" do
      event = holiday_on(Time.zone.local(2026, 11, 10))
      described_class.no_class_spans_between(*range)
      event.destroy!

      expect(described_class.no_class_spans_between(*range)).to be_empty
    end
  end

  describe "category facts" do
    it "gives one badge tone per category" do
      tones = %w[holiday study_day finals deadline registration term_dates academic campus_event].index_with { |c| described_class.category_tone(c) }

      expect(tones).to eq("holiday" => :danger, "study_day" => :danger, "finals" => :danger, "deadline" => :warning,
                          "registration" => :warning, "term_dates" => :info, "academic" => :info, "campus_event" => :neutral)
      expect(described_class.category_tone(nil)).to eq(:neutral)
    end

    it "stores holidays and study days as all-day events" do
      expect(%w[holiday study_day finals].map { |c| described_class.all_day_category?(c) }).to eq([ true, true, false ])
    end

    it ".finals_periods leaves out a finals announcement" do
      period = create(:university_calendar_event, category: "finals", summary: "Final exam period")
      create(:university_calendar_event, category: "finals", summary: "Final Exam Schedule Online")

      expect(described_class.finals_periods).to contain_exactly(period)
    end
  end

  describe "instance helpers" do
    it "#excludes_classes? is true for holiday, study_day and finals" do
      expect(%w[holiday study_day finals].map { |c| build(:university_calendar_event, category: c).excludes_classes? }).to all(be(true))
      expect(build(:university_calendar_event, category: "deadline").excludes_classes?).to be(false)
    end

    it "#formatted_date shows only the date for an all-day event" do
      event = build(:university_calendar_event, all_day: true, start_time: Time.zone.local(2026, 9, 7, 0, 0))

      expect(event.formatted_date).to eq("September 07, 2026")
    end

    it "#formatted_date shows the time for a timed event" do
      event = build(:university_calendar_event, start_time: Time.zone.local(2026, 9, 7, 14, 30))

      expect(event.formatted_date).to eq("September 07, 2026 at 2:30 PM")
    end

    it "#formatted_holiday_summary adds No Classes when the summary lacks it" do
      expect(build(:university_calendar_event, summary: "Labor Day").formatted_holiday_summary).to eq("🏫 Labor Day - No Classes")
    end

    it "#formatted_holiday_summary keeps a summary that already says no classes" do
      expect(build(:university_calendar_event, summary: "No Classes - Fall Break").formatted_holiday_summary).to eq("🏫 No Classes - Fall Break")
    end
  end
end
