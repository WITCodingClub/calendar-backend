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

    {
      holidays: "holiday", term_dates: "term_dates", registration: "registration", deadlines: "deadline",
      study_days: "study_day", finals: "finals", graduation: "graduation", academic: "academic",
      campus_events: "campus_event"
    }.each do |scope_name, category|
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

    it ".past returns events that started before now" do
      past = event_in("holiday", start_time: 1.day.ago, end_time: 1.day.ago + 1.hour)
      event_in("holiday", start_time: 1.day.from_now, end_time: 2.days.from_now)

      expect(described_class.past).to contain_exactly(past)
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

    it ".holidays_between returns holidays in the range, earliest first" do
      later = event_in("holiday", start_time: Time.zone.local(2026, 11, 20, 9, 0), end_time: Time.zone.local(2026, 11, 20, 10, 0))
      earlier = event_in("holiday", start_time: Time.zone.local(2026, 11, 10, 9, 0), end_time: Time.zone.local(2026, 11, 10, 10, 0))
      event_in("finals", start_time: Time.zone.local(2026, 11, 15, 9, 0), end_time: Time.zone.local(2026, 11, 15, 10, 0))

      expect(described_class.holidays_between(Date.new(2026, 11, 1), Date.new(2026, 11, 30))).to eq([ earlier, later ])
    end

    it ".no_class_days_between returns holidays, study days and finals only" do
      holiday = event_in("holiday", start_time: Time.zone.local(2026, 11, 10, 9, 0), end_time: Time.zone.local(2026, 11, 10, 10, 0))
      study = event_in("study_day", start_time: Time.zone.local(2026, 11, 11, 9, 0), end_time: Time.zone.local(2026, 11, 11, 10, 0))
      finals = event_in("finals", start_time: Time.zone.local(2026, 11, 12, 9, 0), end_time: Time.zone.local(2026, 11, 12, 10, 0))
      event_in("deadline", start_time: Time.zone.local(2026, 11, 13, 9, 0), end_time: Time.zone.local(2026, 11, 13, 10, 0))

      expect(described_class.no_class_days_between(Date.new(2026, 11, 1), Date.new(2026, 11, 30))).to eq([ holiday, study, finals ])
    end
  end

  describe ".infer_category" do
    {
      "Thanksgiving Recess" => "holiday",
      "Spring Break" => "holiday",
      "Labor Day" => "holiday",
      "Martin Luther King Jr. Day" => "holiday",
      "No Classes" => "holiday",
      "Juneteenth" => "holiday",
      "Classes Begin" => "term_dates",
      "Last Day of Classes" => "term_dates",
      "Study Day" => "study_day",
      "Reading Period" => "study_day",
      "Final Exam Period" => "finals",
      "Finals Week" => "finals",
      "Commencement" => "graduation",
      "Registration Opens" => "registration",
      "Add/Drop Period" => "registration",
      "Last day to withdraw" => "deadline",
      "Tuition Due" => "deadline"
    }.each do |summary, category|
      it "puts #{summary.inspect} in #{category}" do
        expect(described_class.infer_category(summary, nil)).to eq(category)
      end
    end

    {
      "Calendar Announcement" => "academic",
      "Meeting" => "meeting",
      "Art Exhibit" => "exhibit",
      "Showcase" => "exhibit",
      "Announcement" => "announcement",
      "Something else" => "campus_event"
    }.each do |raw, category|
      it "falls back to #{category} for the raw type #{raw.inspect}" do
        expect(described_class.infer_category("Nothing special", raw)).to eq(category)
      end
    end

    it "handles nil input" do
      expect(described_class.infer_category(nil, nil)).to eq("campus_event")
    end
  end

  describe "summary matchers" do
    it ".registration_summary? matches registration text" do
      expect(described_class.registration_summary?("Fall Registration Opens")).to be(true)
      expect(described_class.registration_summary?("Course Schedule Posted")).to be(false)
    end

    it ".schedule_available_summary? matches schedule releases but not registration" do
      expect(described_class.schedule_available_summary?("Course Schedule Available")).to be(true)
      expect(described_class.schedule_available_summary?("Schedule posted")).to be(true)
      expect(described_class.schedule_available_summary?("Registration schedule available")).to be(false)
      expect(described_class.schedule_available_summary?("Commencement")).to be(false)
    end

    it ".finals_period_summary? matches exam periods but not schedule releases" do
      expect(described_class.finals_period_summary?("Final Exam Period")).to be(true)
      expect(described_class.finals_period_summary?("Finals Week")).to be(true)
      expect(described_class.finals_period_summary?("Final exam schedule posted")).to be(false)
      expect(described_class.finals_period_summary?("Commencement")).to be(false)
    end

    it ".extract_explicit_term_from_summary reads the season and the year" do
      expect(described_class.extract_explicit_term_from_summary("Registration for Spring 2027")).to eq(season: :spring, year: 2027)
      expect(described_class.extract_explicit_term_from_summary("FALL 2026 begins")).to eq(season: :fall, year: 2026)
      expect(described_class.extract_explicit_term_from_summary("Summer 2026")).to eq(season: :summer, year: 2026)
    end

    it ".extract_explicit_term_from_summary returns nil without a term" do
      expect(described_class.extract_explicit_term_from_summary("Commencement 2026")).to be_nil
      expect(described_class.extract_explicit_term_from_summary(nil)).to be_nil
    end
  end

  describe ".generated_term_uid" do
    it "builds a uid for each season" do
      expect(described_class.generated_term_uid(2026, :fall)).to eq(202710)
      expect(described_class.generated_term_uid(2026, :spring)).to eq(202620)
      expect(described_class.generated_term_uid(2026, "summer")).to eq(202630)
    end

    it "returns nil for an unknown season" do
      expect(described_class.generated_term_uid(2026, :winter)).to be_nil
    end
  end

  describe ".term_detection_date_window" do
    it "gives a window for each season" do
      expect(described_class.term_detection_date_window(2026, :spring)).to eq(Date.new(2025, 8, 1)..Date.new(2026, 6, 30))
      expect(described_class.term_detection_date_window(2026, :summer)).to eq(Date.new(2026, 1, 1)..Date.new(2026, 8, 31))
      expect(described_class.term_detection_date_window(2026, :fall)).to eq(Date.new(2026, 1, 1)..Date.new(2026, 12, 31))
    end

    it "gives a wide window for an unknown season" do
      expect(described_class.term_detection_date_window(2026, :winter)).to eq(Date.new(2025, 1, 1)..Date.new(2027, 12, 31))
    end
  end

  describe ".event_matches_term_for_date_detection?" do
    let(:term) { create(:term, year: 2031, season: :fall) }

    def matches?(event, season: :fall, year: 2031, with_term: nil)
      described_class.event_matches_term_for_date_detection?(event, year, season, with_term)
    end

    it "trusts an explicit term in the summary" do
      event = build(:university_calendar_event, summary: "Fall 2031 Registration")

      expect(matches?(event)).to be(true)
      expect(matches?(event, season: :spring)).to be(false)
      expect(matches?(event, year: 2030)).to be(false)
    end

    it "matches an event linked to the term" do
      event = build(:university_calendar_event, term: term)

      expect(matches?(event, with_term: term)).to be(true)
    end

    it "does not match an event with no hint" do
      event = build(:university_calendar_event, summary: "Open house")

      expect(matches?(event)).to be(false)
    end

    it "matches a summary that names the season and the year apart" do
      event = build(:university_calendar_event, summary: "Fall semester 2031 info")

      expect(matches?(event)).to be(true)
    end

    it "matches by academic term and the date window" do
      inside = build(:university_calendar_event, summary: "Open house", academic_term: "Fall Semester",
                                                 start_time: Time.zone.local(2031, 8, 1, 9, 0))
      outside = build(:university_calendar_event, summary: "Open house", academic_term: "Fall Semester",
                                                  start_time: Time.zone.local(2033, 8, 1, 9, 0))

      expect(matches?(inside)).to be(true)
      expect(matches?(outside)).to be(false)
    end

    it "does not match another season's academic term" do
      event = build(:university_calendar_event, summary: "Open house", academic_term: "Spring Semester",
                                                start_time: Time.zone.local(2031, 8, 1, 9, 0))

      expect(matches?(event)).to be(false)
    end

    it "does not match when the start time is missing" do
      event = build(:university_calendar_event, summary: "Open house", academic_term: "Fall Semester", start_time: nil)

      expect(matches?(event)).to be(false)
    end
  end

  describe ".fallback_end_date_from_courses" do
    it "returns nil without a term" do
      expect(described_class.fallback_end_date_from_courses(nil)).to be_nil
    end

    it "returns the latest course end date in the term year range" do
      term = create(:term, year: 2031, season: :fall)
      create(:course, term: term, start_date: Date.new(2031, 9, 1), end_date: Date.new(2031, 12, 10))
      create(:course, term: term, start_date: Date.new(2031, 9, 1), end_date: Date.new(2031, 12, 18))
      create(:course, term: term, start_date: Date.new(2031, 9, 1), end_date: Date.new(2034, 12, 31))

      expect(described_class.fallback_end_date_from_courses(term)).to eq(Date.new(2031, 12, 18))
    end
  end

  describe ".leopard_web_registration_open_date" do
    include ActiveSupport::Testing::TimeHelpers

    around { |example| travel_to(Time.zone.local(2026, 10, 9, 12, 0)) { example.run } }

    let(:term) { create(:term, year: 2031, season: :fall) }

    def stub_active_terms(result)
      allow(Catalog::LeopardWebClient).to receive(:get_active_terms).and_return(result)
    end

    it "returns nil when Banner fails" do
      stub_active_terms(success: false, terms: [])

      expect(described_class.leopard_web_registration_open_date(2031, :fall, term)).to be_nil
    end

    it "returns nil when the term is not active" do
      stub_active_terms(success: true, terms: [ { code: "209910" } ])

      expect(described_class.leopard_web_registration_open_date(2031, :fall, term)).to be_nil
    end

    it "returns today when the term has no start date yet" do
      stub_active_terms(success: true, terms: [ { code: term.uid.to_s } ])

      expect(described_class.leopard_web_registration_open_date(2031, :fall, term)).to eq(Time.zone.today)
    end

    it "keeps a stored start date that is in the past" do
      term.update!(start_date: Date.new(2026, 9, 1))
      stub_active_terms(success: true, terms: [ { "code" => term.uid } ])

      expect(described_class.leopard_web_registration_open_date(2031, :fall, term)).to eq(Date.new(2026, 9, 1))
    end

    it "uses a generated uid when there is no term row" do
      stub_active_terms(success: true, terms: [ { code: "203210" } ])

      expect(described_class.leopard_web_registration_open_date(2031, :fall, nil)).to eq(Time.zone.today)
    end

    it "returns nil for an unknown season without a term" do
      stub_active_terms(success: true, terms: [])

      expect(described_class.leopard_web_registration_open_date(2031, :winter, nil)).to be_nil
    end

    it "reports an error and returns nil" do
      allow(Catalog::LeopardWebClient).to receive(:get_active_terms).and_raise(StandardError, "boom")
      allow(Rails.error).to receive(:report)

      expect(described_class.leopard_web_registration_open_date(2031, :fall, term)).to be_nil
      expect(Rails.error).to have_received(:report).with(an_instance_of(StandardError), handled: true, context: { year: 2031, season: "fall" })
    end
  end

  describe ".detect_term_dates" do
    let(:term) { create(:term, year: 2031, season: :fall) }

    before { allow(Catalog::LeopardWebClient).to receive(:get_active_terms).and_return(success: false, terms: []) }

    def event_at(summary, start_time, end_time: start_time + 1.hour, **attrs)
      create(:university_calendar_event, summary: summary, start_time: start_time, end_time: end_time, **attrs)
    end

    it "uses the schedule release event for the start date and the finals period for the end date" do
      event_at("Fall 2031 Course Schedule Available", Time.zone.local(2031, 3, 20, 9, 0))
      event_at("Fall 2031 Final Exam Period", Time.zone.local(2031, 12, 10, 9, 0), end_time: Time.zone.local(2031, 12, 17, 17, 0), category: "finals")

      expect(described_class.detect_term_dates(2031, :fall)).to eq(start_date: Date.new(2031, 3, 20), end_date: Date.new(2031, 12, 17))
    end

    it "estimates the start date as 14 days before registration" do
      event_at("Fall 2031 Registration Opens", Time.zone.local(2031, 4, 15, 9, 0))

      expect(described_class.detect_term_dates(2031, :fall)[:start_date]).to eq(Date.new(2031, 4, 1))
    end

    it "prefers the LeopardWeb registration date" do
      allow(Catalog::LeopardWebClient).to receive(:get_active_terms).and_return(success: true, terms: [ { code: term.uid } ])
      event_at("Fall 2031 Course Schedule Available", Time.zone.local(2031, 3, 20, 9, 0))

      expect(described_class.detect_term_dates(2031, :fall)[:start_date]).to eq(Time.zone.today)
    end

    it "falls back to course end dates when there is no finals event" do
      create(:course, term: term, start_date: Date.new(2031, 9, 1), end_date: Date.new(2031, 12, 12))

      expect(described_class.detect_term_dates(2031, :fall)).to eq(start_date: nil, end_date: Date.new(2031, 12, 12))
    end

    it "returns nil dates when nothing matches" do
      expect(described_class.detect_term_dates(2031, :fall)).to eq(start_date: nil, end_date: nil)
    end
  end

  describe "instance helpers" do
    it "#term_boundary_event? is true for term_dates only" do
      expect(build(:university_calendar_event, category: "term_dates").term_boundary_event?).to be(true)
      expect(build(:university_calendar_event, category: "holiday").term_boundary_event?).to be(false)
    end

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

    it "#duration_hours is nil for an all-day event" do
      expect(build(:university_calendar_event, all_day: true).duration_hours).to be_nil
    end

    it "#duration_hours rounds to one decimal" do
      event = build(:university_calendar_event, start_time: Time.zone.local(2026, 9, 7, 9, 0), end_time: Time.zone.local(2026, 9, 7, 10, 40))

      expect(event.duration_hours).to eq(1.7)
    end

    it "#formatted_holiday_summary adds No Classes when the summary lacks it" do
      expect(build(:university_calendar_event, summary: "Labor Day").formatted_holiday_summary).to eq("🏫 Labor Day - No Classes")
    end

    it "#formatted_holiday_summary keeps a summary that already says no classes" do
      expect(build(:university_calendar_event, summary: "No Classes - Fall Break").formatted_holiday_summary).to eq("🏫 No Classes - Fall Break")
    end
  end
end
