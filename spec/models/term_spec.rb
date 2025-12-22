# frozen_string_literal: true

# == Schema Information
#
# Table name: terms
# Database name: primary
#
#  id                  :bigint           not null, primary key
#  catalog_imported    :boolean          default(FALSE), not null
#  catalog_imported_at :datetime
#  end_date            :date
#  season              :integer
#  start_date          :date
#  uid                 :integer          not null
#  year                :integer
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
# Indexes
#
#  index_terms_on_uid              (uid) UNIQUE
#  index_terms_on_year_and_season  (year,season) UNIQUE
#
require "rails_helper"

RSpec.describe Term do
  describe "validations" do
    it "validates presence of uid" do
      term = build(:term, uid: nil)
      expect(term).not_to be_valid
      expect(term.errors[:uid]).to include("can't be blank")
    end

    it "validates uniqueness of uid" do
      create(:term, uid: 202610, year: 2025, season: :fall)
      duplicate_term = build(:term, uid: 202610, year: 2026, season: :spring)
      expect(duplicate_term).not_to be_valid
      expect(duplicate_term.errors[:uid]).to include("has already been taken")
    end
  end

  describe "associations" do
    it "has many courses" do
      term = create(:term)
      expect(term).to respond_to(:courses)
    end

    it "has many enrollments" do
      term = create(:term)
      expect(term).to respond_to(:enrollments)
    end
  end

  describe ".find_by_uid" do
    let!(:term) { create(:term, uid: 202610, year: 2025, season: :fall) }

    it "finds term by uid" do
      expect(described_class.find_by(uid: 202610)).to eq(term)
    end

    it "returns nil if term not found" do
      expect(described_class.find_by(uid: 999999)).to be_nil
    end
  end

  describe ".find_by_uid!" do
    let!(:term) { create(:term, uid: 202610, year: 2025, season: :fall) }

    it "finds term by uid" do
      expect(described_class.find_by!(uid: 202610)).to eq(term)
    end

    it "raises ActiveRecord::RecordNotFound if term not found" do
      expect {
        described_class.find_by!(uid: 999999)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe ".current" do
    context "in fall semester (Aug-Dec)" do
      before do
        travel_to Date.new(2025, 10, 15)
        create(:term, uid: 202610, year: 2025, season: :fall)
      end

      after { travel_back }

      it "returns the fall term" do
        expect(described_class.current.season).to eq("fall")
        expect(described_class.current.year).to eq(2025)
      end
    end

    context "in spring semester (Jan-May)" do
      before do
        travel_to Date.new(2025, 3, 15)
        create(:term, uid: 202520, year: 2025, season: :spring)
      end

      after { travel_back }

      it "returns the spring term" do
        expect(described_class.current.season).to eq("spring")
        expect(described_class.current.year).to eq(2025)
      end
    end

    context "in summer semester (Jun-Jul)" do
      before do
        travel_to Date.new(2025, 7, 15)
        create(:term, uid: 202530, year: 2025, season: :summer)
      end

      after { travel_back }

      it "returns the summer term" do
        expect(described_class.current.season).to eq("summer")
        expect(described_class.current.year).to eq(2025)
      end
    end
  end

  describe ".next" do
    context "when current term is fall" do
      before do
        travel_to Date.new(2025, 10, 15)
        create(:term, uid: 202610, year: 2025, season: :fall)
        create(:term, uid: 202620, year: 2026, season: :spring)
      end

      after { travel_back }

      it "returns spring of next year" do
        expect(described_class.next.season).to eq("spring")
        expect(described_class.next.year).to eq(2026)
      end
    end

    context "when current term is spring" do
      before do
        travel_to Date.new(2025, 3, 15)
        create(:term, uid: 202520, year: 2025, season: :spring)
        create(:term, uid: 202530, year: 2025, season: :summer)
      end

      after { travel_back }

      it "returns summer of same year" do
        expect(described_class.next.season).to eq("summer")
        expect(described_class.next.year).to eq(2025)
      end
    end

    context "when current term is summer" do
      before do
        travel_to Date.new(2025, 7, 15)
        create(:term, uid: 202530, year: 2025, season: :summer)
        create(:term, uid: 202610, year: 2025, season: :fall)
      end

      after { travel_back }

      it "returns fall of same year" do
        expect(described_class.next.season).to eq("fall")
        expect(described_class.next.year).to eq(2025)
      end
    end
  end

  describe ".current_uid" do
    before do
      travel_to Date.new(2025, 10, 15)
      create(:term, uid: 202610, year: 2025, season: :fall)
    end

    after { travel_back }

    it "returns the uid of the current term" do
      expect(described_class.current_uid).to eq(202610)
    end

    it "returns nil if no current term exists" do
      described_class.destroy_all
      expect(described_class.current_uid).to be_nil
    end
  end

  describe ".next_uid" do
    before do
      travel_to Date.new(2025, 10, 15)
      create(:term, uid: 202610, year: 2025, season: :fall)
      create(:term, uid: 202620, year: 2026, season: :spring)
    end

    after { travel_back }

    it "returns the uid of the next term" do
      expect(described_class.next_uid).to eq(202620)
    end

    it "returns nil if no next term exists" do
      described_class.find_by(uid: 202620).destroy
      expect(described_class.next_uid).to be_nil
    end
  end

  describe ".exists_by_uid?" do
    let!(:term) { create(:term, uid: 202610, year: 2025, season: :fall) }

    it "returns true if term exists" do
      expect(described_class.exists_by_uid?(202610)).to be true
    end

    it "returns false if term does not exist" do
      expect(described_class.exists_by_uid?(999999)).to be false
    end
  end

  describe "#name" do
    it "returns formatted name for fall term" do
      term = build(:term, year: 2025, season: :fall)
      expect(term.name).to eq("Fall 2025")
    end

    it "returns formatted name for spring term" do
      term = build(:term, year: 2025, season: :spring)
      expect(term.name).to eq("Spring 2025")
    end

    it "returns formatted name for summer term" do
      term = build(:term, year: 2025, season: :summer)
      expect(term.name).to eq("Summer 2025")
    end
  end

  describe "#update_dates_from_courses!" do
    let(:term) { create(:term, year: 2025, season: :fall) }

    it "updates start_date to earliest course start_date" do
      create(:course, term: term, start_date: Date.new(2025, 8, 20))
      create(:course, term: term, start_date: Date.new(2025, 8, 15))
      create(:course, term: term, start_date: Date.new(2025, 8, 25))

      term.update_dates_from_courses!
      expect(term.start_date).to eq(Date.new(2025, 8, 15))
    end

    it "updates end_date to latest course end_date" do
      create(:course, term: term, end_date: Date.new(2025, 12, 10))
      create(:course, term: term, end_date: Date.new(2025, 12, 20))
      create(:course, term: term, end_date: Date.new(2025, 12, 15))

      term.update_dates_from_courses!
      expect(term.end_date).to eq(Date.new(2025, 12, 20))
    end

    it "ignores courses with nil dates" do
      create(:course, term: term, start_date: Date.new(2025, 8, 15), end_date: Date.new(2025, 12, 15))
      create(:course, term: term, start_date: nil, end_date: nil)

      term.update_dates_from_courses!
      expect(term.start_date).to eq(Date.new(2025, 8, 15))
      expect(term.end_date).to eq(Date.new(2025, 12, 15))
    end

    it "does not update if no courses exist" do
      term.update_dates_from_courses!
      expect(term.start_date).to be_nil
      expect(term.end_date).to be_nil
    end
  end

  describe "#active?" do
    let(:term) { create(:term, year: 2025, season: :fall, start_date: Date.new(2025, 8, 15), end_date: Date.new(2025, 12, 20)) }

    it "returns true when today is within term dates" do
      travel_to Date.new(2025, 10, 15)
      expect(term.active?).to be true
      travel_back
    end

    it "returns true on start_date" do
      travel_to Date.new(2025, 8, 15)
      expect(term.active?).to be true
      travel_back
    end

    it "returns true on end_date" do
      travel_to Date.new(2025, 12, 20)
      expect(term.active?).to be true
      travel_back
    end

    it "returns false when today is before start_date" do
      travel_to Date.new(2025, 8, 1)
      expect(term.active?).to be false
      travel_back
    end

    it "returns false when today is after end_date" do
      travel_to Date.new(2025, 12, 25)
      expect(term.active?).to be false
      travel_back
    end

    it "returns false when dates are not set" do
      term.update!(start_date: nil, end_date: nil)
      expect(term.active?).to be false
    end
  end

  describe "#upcoming?" do
    let(:term) { create(:term, year: 2025, season: :fall, start_date: Date.new(2025, 8, 15)) }

    it "returns true when start_date is in the future" do
      travel_to Date.new(2025, 8, 1)
      expect(term.upcoming?).to be true
      travel_back
    end

    it "returns false when start_date is today" do
      travel_to Date.new(2025, 8, 15)
      expect(term.upcoming?).to be false
      travel_back
    end

    it "returns false when start_date is in the past" do
      travel_to Date.new(2025, 8, 20)
      expect(term.upcoming?).to be false
      travel_back
    end

    it "returns false when start_date is not set" do
      term.update!(start_date: nil)
      expect(term.upcoming?).to be false
    end
  end

  describe ".current with date-based logic" do
    it "finds term where today falls within start_date and end_date" do
      travel_to Date.new(2025, 10, 15)

      # Create a fall term with actual date ranges
      fall_term = create(:term, year: 2025, season: :fall, start_date: Date.new(2025, 8, 15), end_date: Date.new(2025, 12, 20))

      expect(described_class.current).to eq(fall_term)
      travel_back
    end

    it "falls back to season-based logic when no term has dates" do
      travel_to Date.new(2025, 10, 15)

      # Create term without dates
      fall_term = create(:term, year: 2025, season: :fall, start_date: nil, end_date: nil)

      expect(described_class.current).to eq(fall_term)
      travel_back
    end
  end

  describe ".next with date-based logic" do
    it "finds next term by start_date" do
      travel_to Date.new(2025, 10, 15)

      # Current term
      create(:term, year: 2025, season: :fall, start_date: Date.new(2025, 8, 15), end_date: Date.new(2025, 12, 20))

      # Next term
      spring_term = create(:term, year: 2026, season: :spring, start_date: Date.new(2026, 1, 15), end_date: Date.new(2026, 5, 15))

      # Future term
      create(:term, year: 2026, season: :summer, start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 7, 31))

      expect(described_class.next).to eq(spring_term)
      travel_back
    end

    it "falls back to season-based logic when no terms have dates" do
      travel_to Date.new(2025, 10, 15)

      # Current term without dates
      create(:term, year: 2025, season: :fall, start_date: nil, end_date: nil)

      # Next term without dates
      spring_term = create(:term, year: 2026, season: :spring, start_date: nil, end_date: nil)

      expect(described_class.next).to eq(spring_term)
      travel_back
    end
  end
end
