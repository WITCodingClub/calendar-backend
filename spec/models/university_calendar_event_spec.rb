# frozen_string_literal: true

require "rails_helper"

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

  describe ".category_description" do
    it "describes every category" do
      descriptions = UniversityCalendarEvent::CATEGORIES.map { |category| described_class.category_description(category) }

      expect(descriptions).to all(be_present)
    end

    it "returns the description of a known category" do
      expect(described_class.category_description("finals")).to eq("Final exam schedules and exam periods")
    end

    it "falls back for an unknown category" do
      expect(described_class.category_description("parties")).to eq("Other university events")
    end
  end
end
