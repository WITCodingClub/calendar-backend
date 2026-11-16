# frozen_string_literal: true

require "rails_helper"

RSpec.describe UniversityCalendar::DuplicateMatcher do
  describe ".similar?" do
    it "matches titles that share their main words" do
      expect(described_class.similar?("Wellbeing Day", "Campus Wellbeing Day - No Classes")).to be(true)
    end

    it "does not match different events" do
      expect(described_class.similar?("Labor Day", "Registration Opens")).to be(false)
    end

    it "handles nil" do
      expect(described_class.similarity(nil, "Labor Day")).to eq(0.0)
      expect(described_class.similarity(nil, nil)).to eq(1.0)
    end
  end

  describe ".preferred_event" do
    it "keeps the copy of the office with the highest priority, then the one fetched last" do
      registrar = build(:university_calendar_event, organization: "Registrar's Office", created_at: Time.current)
      other     = build(:university_calendar_event, organization: "Some Club", created_at: Time.current,
                                                    last_fetched_at: Time.current)
      newer     = build(:university_calendar_event, organization: "Some Club", created_at: Time.current,
                                                    last_fetched_at: 1.hour.from_now)

      expect(described_class.preferred_event([ other, registrar ])).to eq(registrar)
      expect(described_class.preferred_event([ other, newer ])).to eq(newer)
    end
  end
end
