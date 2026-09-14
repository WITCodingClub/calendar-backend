# frozen_string_literal: true

# == Schema Information
#
# Table name: terms
#
#  id                    :bigint           not null, primary key
#  catalog_import_failed :boolean          default(FALSE), not null
#  catalog_imported      :boolean          default(FALSE), not null
#  catalog_imported_at   :datetime
#  catalog_importing     :boolean          default(FALSE), not null
#  end_date              :date
#  season                :integer          not null
#  start_date            :date
#  uid                   :integer          not null
#  year                  :integer          not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  catalog_import_job_id :string
#
# Indexes
#
#  index_terms_on_uid              (uid) UNIQUE
#  index_terms_on_year_and_season  (year,season) UNIQUE
#
require "rails_helper"

RSpec.describe Term, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  describe "associations and validations" do
    subject { create(:term) }

    it { is_expected.to have_many(:courses).dependent(:destroy) }
    it { is_expected.to have_many(:enrollments).through(:courses) }
    it { is_expected.to have_many(:final_exams).dependent(:destroy) }
    it { is_expected.to have_many(:university_calendar_events).dependent(:nullify) }

    it { is_expected.to validate_presence_of(:uid) }
    it { is_expected.to validate_uniqueness_of(:uid) }

    it { is_expected.to define_enum_for(:season).with_values(spring: 1, fall: 2, summer: 3).backed_by_column_of_type(:integer) }
  end

  def create_term(year:, season:, **attrs)
    create(:term, year: year, season: season, **attrs)
  end

  describe ".chronological / .reverse_chronological" do
    it "orders seasons within a year as spring, summer, fall despite enum values" do
      fall        = create_term(year: 2026, season: :fall)
      spring      = create_term(year: 2026, season: :spring)
      summer      = create_term(year: 2026, season: :summer)
      spring_next = create_term(year: 2027, season: :spring)

      expect(described_class.chronological.to_a).to eq([ spring, summer, fall, spring_next ])
      expect(described_class.reverse_chronological.to_a).to eq([ spring_next, fall, summer, spring ])
    end
  end

  describe ".current_and_future" do
    it "includes fall of the current year during the summer term" do
      travel_to Date.new(2026, 7, 11) do
        create_term(year: 2026, season: :spring)
        summer      = create_term(year: 2026, season: :summer)
        fall        = create_term(year: 2026, season: :fall)
        spring_next = create_term(year: 2027, season: :spring)

        expect(described_class.current_and_future.to_a).to eq([ spring_next, fall, summer ])
      end
    end

    it "excludes summer of the current year during the fall term" do
      travel_to Date.new(2026, 10, 1) do
        create_term(year: 2026, season: :spring)
        create_term(year: 2026, season: :summer)
        fall        = create_term(year: 2026, season: :fall)
        spring_next = create_term(year: 2027, season: :spring)

        expect(described_class.current_and_future.to_a).to eq([ spring_next, fall ])
      end
    end
  end

  describe ".enrolled_for" do
    it "returns only terms the user has enrollments in" do
      user       = create(:user)
      other_user = create(:user)

      enrolled_term = create_term(year: 2026, season: :fall)
      other_term    = create_term(year: 2026, season: :summer)

      course       = create(:course, term: enrolled_term)
      other_course = create(:course, term: other_term)

      create(:enrollment, user: user, course: course, term: enrolled_term)
      create(:enrollment, user: other_user, course: other_course, term: other_term)

      expect(described_class.enrolled_for(user)).to contain_exactly(enrolled_term)
    end
  end

  describe ".season_position" do
    it "maps seasons to chronological positions" do
      expect(described_class.season_position(:spring)).to eq(1)
      expect(described_class.season_position("summer")).to eq(2)
      expect(described_class.season_position(:fall)).to eq(3)
    end
  end
end
