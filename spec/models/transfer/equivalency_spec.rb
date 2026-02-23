# frozen_string_literal: true

# == Schema Information
#
# Table name: transfer_equivalencies
# Database name: primary
#
#  id                 :bigint           not null, primary key
#  effective_date     :date             not null
#  expiration_date    :date
#  notes              :text
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  transfer_course_id :bigint           not null
#  wit_course_id      :bigint           not null
#
# Indexes
#
#  idx_transfer_equivalencies_unique                   (transfer_course_id,wit_course_id) UNIQUE
#  index_transfer_equivalencies_on_effective_date      (effective_date)
#  index_transfer_equivalencies_on_expiration_date     (expiration_date)
#  index_transfer_equivalencies_on_transfer_course_id  (transfer_course_id)
#  index_transfer_equivalencies_on_wit_course_id       (wit_course_id)
#
# Foreign Keys
#
#  fk_rails_...  (transfer_course_id => transfer_courses.id)
#  fk_rails_...  (wit_course_id => courses.id)
#
require "rails_helper"

RSpec.describe Transfer::Equivalency do
  describe "validations" do
    subject { build(:transfer_equivalency) }

    it { is_expected.to validate_presence_of(:effective_date) }

    describe "wit_course_id uniqueness" do
      let(:transfer_course) { create(:transfer_course) }
      let(:wit_course) { create(:course, term: create(:term)) }

      before { create(:transfer_equivalency, transfer_course: transfer_course, wit_course: wit_course) }

      it "validates uniqueness of wit_course_id scoped to transfer_course_id" do
        duplicate = build(:transfer_equivalency, transfer_course: transfer_course, wit_course: wit_course)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:wit_course_id]).to be_present
      end

      it "allows same WIT course for different transfer courses" do
        other_transfer_course = create(:transfer_course)
        other_equivalency = build(:transfer_equivalency, transfer_course: other_transfer_course, wit_course: wit_course)
        expect(other_equivalency).to be_valid
      end
    end

    describe "expiration_after_effective" do
      it "is valid when expiration_date is after effective_date" do
        equivalency = build(:transfer_equivalency, effective_date: 1.year.ago, expiration_date: 1.month.from_now)
        expect(equivalency).to be_valid
      end

      it "is invalid when expiration_date is before effective_date" do
        equivalency = build(:transfer_equivalency, effective_date: 1.year.ago, expiration_date: 2.years.ago)
        expect(equivalency).not_to be_valid
        expect(equivalency.errors[:expiration_date]).to include("must be after effective date")
      end

      it "is invalid when expiration_date equals effective_date" do
        date = Date.current
        equivalency = build(:transfer_equivalency, effective_date: date, expiration_date: date)
        expect(equivalency).not_to be_valid
      end

      it "is valid when expiration_date is nil" do
        equivalency = build(:transfer_equivalency, effective_date: 1.year.ago, expiration_date: nil)
        expect(equivalency).to be_valid
      end
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:transfer_course).class_name("Transfer::Course") }
    it { is_expected.to belong_to(:wit_course).class_name("Course") }
  end

  describe "scopes" do
    let!(:active_equivalency) { create(:transfer_equivalency, expiration_date: nil) }
    let!(:expiring_soon) { create(:transfer_equivalency, :expiring_soon) }
    let!(:expired_equivalency) { create(:transfer_equivalency, :expired) }
    let!(:recent_equivalency) { create(:transfer_equivalency, effective_date: 1.month.ago) }
    let!(:old_equivalency) { create(:transfer_equivalency, effective_date: 2.years.ago) }

    describe ".active" do
      it "returns only active equivalencies" do
        expect(described_class.active).to include(active_equivalency, expiring_soon)
        expect(described_class.active).not_to include(expired_equivalency)
      end
    end

    describe ".expired" do
      it "returns only expired equivalencies" do
        expect(described_class.expired).to include(expired_equivalency)
        expect(described_class.expired).not_to include(active_equivalency, expiring_soon)
      end
    end

    describe ".effective_on" do
      let(:date) { 1.year.ago }

      it "returns equivalencies effective on or before the specified date" do
        expect(described_class.effective_on(date)).to include(old_equivalency)
        expect(described_class.effective_on(date)).not_to include(recent_equivalency)
      end
    end
  end

  describe "#active?" do
    it "returns true when expiration_date is nil" do
      equivalency = create(:transfer_equivalency, expiration_date: nil)
      expect(equivalency.active?).to be true
    end

    it "returns true when expiration_date is in the future" do
      equivalency = create(:transfer_equivalency, :expiring_soon)
      expect(equivalency.active?).to be true
    end

    it "returns false when expiration_date is in the past" do
      equivalency = create(:transfer_equivalency, :expired)
      expect(equivalency.active?).to be false
    end
  end

  describe "#expired?" do
    it "returns false when equivalency is active" do
      equivalency = create(:transfer_equivalency, expiration_date: nil)
      expect(equivalency.expired?).to be false
    end

    it "returns true when equivalency has expired" do
      equivalency = create(:transfer_equivalency, :expired)
      expect(equivalency.expired?).to be true
    end
  end
end
