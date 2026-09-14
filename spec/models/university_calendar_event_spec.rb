# frozen_string_literal: true

require "rails_helper"

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
end
