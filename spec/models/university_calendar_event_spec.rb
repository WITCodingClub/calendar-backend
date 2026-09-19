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
  it { is_expected.to have_many(:google_calendar_events).dependent(:nullify) }

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
