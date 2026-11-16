# frozen_string_literal: true

require "rails_helper"

RSpec.describe UniversityCalendar::TermDates do
  describe "summary matchers" do
    it ".schedule_available_summary? matches schedule releases but not registration" do
      expect(described_class.schedule_available_summary?("Course Schedule Available")).to be(true)
      expect(described_class.schedule_available_summary?("Schedule posted")).to be(true)
      expect(described_class.schedule_available_summary?("Registration schedule available")).to be(false)
      expect(described_class.schedule_available_summary?("Commencement")).to be(false)
    end

    it ".registration_summary? matches registration text only" do
      expect(described_class.registration_summary?("Fall Registration Opens")).to be(true)
      expect(described_class.registration_summary?("Last day to Add/Drop")).to be(false)
    end

    it ".finals_period_summary? matches exam periods but not schedule releases" do
      expect(described_class.finals_period_summary?("Final Exam Period")).to be(true)
      expect(described_class.finals_period_summary?("Finals Week")).to be(true)
      expect(described_class.finals_period_summary?("Final exam schedule posted")).to be(false)
      expect(described_class.finals_period_summary?("Summer 2026 Final Exam Schedule Availabl")).to be(false)
      expect(described_class.finals_period_summary?("Commencement")).to be(false)
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

  describe ".leopard_web_registration_open_date" do
    include ActiveSupport::Testing::TimeHelpers

    around { |example| travel_to(Time.zone.local(2026, 10, 9, 12, 0)) { example.run } }

    let(:term) { create(:term, year: 2031, season: :fall) }

    def stub_active_terms(result)
      allow(Catalog::LeopardWebClient).to receive(:get_active_terms).and_return(result)
    end

    it "returns nil when Banner fails" do
      allow(Catalog::LeopardWebClient).to receive(:get_active_terms).and_raise(Catalog::LeopardWebClient::RequestError, "down")

      expect(described_class.leopard_web_registration_open_date(2031, :fall, term)).to be_nil
    end

    it "returns nil when the term is not active" do
      stub_active_terms([ { code: "209910" } ])

      expect(described_class.leopard_web_registration_open_date(2031, :fall, term)).to be_nil
    end

    it "returns today when the term has no start date yet" do
      stub_active_terms([ { code: term.uid.to_s } ])

      expect(described_class.leopard_web_registration_open_date(2031, :fall, term)).to eq(Time.zone.today)
    end

    it "keeps a stored start date that is in the past" do
      term.update!(start_date: Date.new(2026, 9, 1))
      stub_active_terms([ { code: term.uid } ])

      expect(described_class.leopard_web_registration_open_date(2031, :fall, term)).to eq(Date.new(2026, 9, 1))
    end

    it "uses a generated uid when there is no term row" do
      stub_active_terms([ { code: "203210" } ])

      expect(described_class.leopard_web_registration_open_date(2031, :fall, nil)).to eq(Time.zone.today)
    end

    it "returns nil for an unknown season without a term" do
      stub_active_terms([])

      expect(described_class.leopard_web_registration_open_date(2031, :winter, nil)).to be_nil
    end

    it "reports an error and returns nil" do
      allow(Catalog::LeopardWebClient).to receive(:get_active_terms).and_raise(StandardError, "boom")
      allow(Rails.error).to receive(:report)

      expect(described_class.leopard_web_registration_open_date(2031, :fall, term)).to be_nil
      expect(Rails.error).to have_received(:report).with(an_instance_of(StandardError), handled: true, context: { year: 2031, season: "fall" })
    end
  end

  describe ".detect" do
    include ActiveSupport::Testing::TimeHelpers

    let(:term) { create(:term, year: 2031, season: :fall) }

    before { allow(Catalog::LeopardWebClient).to receive(:get_active_terms).and_raise(Catalog::LeopardWebClient::RequestError, "down") }

    def event_at(summary, start_time, end_time: start_time + 1.hour, **attrs)
      create(:university_calendar_event, summary: summary, start_time: start_time, end_time: end_time, **attrs)
    end

    it "uses the schedule release event for the start date and the finals period for the end date" do
      event_at("Fall 2031 Course Schedule Available", Time.zone.local(2031, 3, 20, 9, 0))
      event_at("Fall 2031 Final Exam Period", Time.zone.local(2031, 12, 10, 9, 0), end_time: Time.zone.local(2031, 12, 17, 17, 0), category: "finals")

      expect(described_class.detect(2031, :fall)).to eq(start_date: Date.new(2031, 3, 20), end_date: Date.new(2031, 12, 17))
    end

    it "estimates the start date as 14 days before registration" do
      event_at("Fall 2031 Registration Opens", Time.zone.local(2031, 4, 15, 9, 0), category: "registration")

      expect(described_class.detect(2031, :fall)[:start_date]).to eq(Date.new(2031, 4, 1))
    end

    it "prefers the LeopardWeb registration date" do
      allow(Catalog::LeopardWebClient).to receive(:get_active_terms).and_return([ { code: term.uid } ])
      event_at("Fall 2031 Course Schedule Available", Time.zone.local(2031, 3, 20, 9, 0))

      travel_to(Time.zone.local(2031, 4, 2, 12)) do
        expect(described_class.detect(2031, :fall)[:start_date]).to eq(Date.new(2031, 4, 2))
      end
    end

    it "ignores a LeopardWeb listing that comes before the term's window" do
      allow(Catalog::LeopardWebClient).to receive(:get_active_terms).and_return([ { code: term.uid } ])

      travel_to(Time.zone.local(2030, 7, 25, 12)) do
        expect(described_class.detect(2031, :fall)[:start_date]).to be_nil
      end
    end

    # Summer 2027 got 2026-07-25 and 2026-08-11: LeopardWeb listed it in July
    # 2026, and the Summer 2026 finals event carried its term id.
    it "keeps a summer term's dates out of the year before" do
      summer = create(:term, year: 2031, season: :summer)
      allow(Catalog::LeopardWebClient).to receive(:get_active_terms).and_return([ { code: summer.uid } ])
      event_at("Final Exam Period", Time.zone.local(2030, 8, 5, 9, 0), end_time: Time.zone.local(2030, 8, 11, 17, 0),
                                    category: "finals", term: summer)

      travel_to(Time.zone.local(2030, 7, 25, 12)) do
        expect(described_class.detect(2031, :summer)).to eq(start_date: nil, end_date: nil)
      end
    end

    it "accepts a spring term's registration date in the fall before" do
      create(:term, year: 2031, season: :spring)
      event_at("Spring 2031 Course Schedule Available", Time.zone.local(2030, 10, 15, 9, 0))
      event_at("Spring 2031 Final Exam Period", Time.zone.local(2031, 4, 20, 9, 0), end_time: Time.zone.local(2031, 4, 25, 17, 0), category: "finals")

      expect(described_class.detect(2031, :spring)).to eq(start_date: Date.new(2030, 10, 15), end_date: Date.new(2031, 4, 25))
    end

    it "falls back to course end dates when there is no finals event" do
      create(:course, term: term, start_date: Date.new(2031, 9, 1), end_date: Date.new(2031, 12, 12))

      expect(described_class.detect(2031, :fall)).to eq(start_date: nil, end_date: Date.new(2031, 12, 12))
    end

    it "uses a finals week or a final exams event for the end date" do
      event_at("Finals Week", Time.zone.local(2031, 12, 10, 9, 0), end_time: Time.zone.local(2031, 12, 16, 17, 0),
                              category: "finals", term: term)
      event_at("Fall 2031 Final Exams", Time.zone.local(2031, 12, 12, 9, 0), end_time: Time.zone.local(2031, 12, 19, 17, 0), category: "finals")

      expect(described_class.detect(2031, :fall)[:end_date]).to eq(Date.new(2031, 12, 19))
    end

    it "does not take an add/drop deadline for the registration event" do
      event_at("Fall 2031 Last day to Add/Drop", Time.zone.local(2031, 3, 1, 9, 0), category: "registration")
      event_at("Fall 2031 Registration Opens", Time.zone.local(2031, 4, 15, 9, 0), category: "registration")

      expect(described_class.detect(2031, :fall)[:start_date]).to eq(Date.new(2031, 4, 1))
    end

    it "ignores a finals announcement for the end date" do
      event_at("Fall 2031 Final Exam Schedule Online", Time.zone.local(2031, 12, 28, 9, 0), category: "finals")

      expect(described_class.detect(2031, :fall)[:end_date]).to be_nil
    end

    it "returns nil dates when nothing matches" do
      expect(described_class.detect(2031, :fall)).to eq(start_date: nil, end_date: nil)
    end
  end
end
