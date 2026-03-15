# frozen_string_literal: true

require "rails_helper"

RSpec.describe EnrollmentSnapshot do
  describe "associations" do
    it "belongs to a user" do
      expect(described_class.reflect_on_association(:user).macro).to eq(:belongs_to)
    end

    it "belongs to a term" do
      expect(described_class.reflect_on_association(:term).macro).to eq(:belongs_to)
    end
  end

  describe "validations" do
    let(:user) { create(:user) }
    let(:term) { create(:term) }

    it "requires a crn" do
      snapshot = described_class.new(user: user, term: term, snapshot_created_at: Time.current)
      expect(snapshot).not_to be_valid
      expect(snapshot.errors[:crn]).to be_present
    end

    it "requires a unique crn per user and term" do
      described_class.create!(user: user, term: term, crn: 11111, snapshot_created_at: Time.current)
      duplicate = described_class.new(user: user, term: term, crn: 11111, snapshot_created_at: Time.current)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:crn]).to be_present
    end

    it "allows the same crn for a different user" do
      other_user = create(:user)
      described_class.create!(user: user, term: term, crn: 22222, snapshot_created_at: Time.current)
      other_snapshot = described_class.new(user: other_user, term: term, crn: 22222, snapshot_created_at: Time.current)
      expect(other_snapshot).to be_valid
    end

    it "allows the same crn for a different term" do
      other_term = create(:term)
      described_class.create!(user: user, term: term, crn: 33333, snapshot_created_at: Time.current)
      other_snapshot = described_class.new(user: user, term: other_term, crn: 33333, snapshot_created_at: Time.current)
      expect(other_snapshot).to be_valid
    end
  end

  describe "scopes" do
    let(:user) { create(:user) }
    let(:term) { create(:term) }
    let!(:restoration_snapshot) do
      described_class.create!(user: user, term: term, crn: 44444,
        snapshot_created_at: Time.current,
        snapshot_reason: "Pre-CRN-uniqueness-fix backup")
    end
    let!(:other_snapshot) do
      described_class.create!(user: user, term: create(:term), crn: 55555,
        snapshot_created_at: Time.current,
        snapshot_reason: "Other reason")
    end

    describe ".for_restoration" do
      it "returns only snapshots with the restoration reason" do
        expect(described_class.for_restoration).to include(restoration_snapshot)
        expect(described_class.for_restoration).not_to include(other_snapshot)
      end
    end

    describe ".for_term" do
      it "returns only snapshots for the given term" do
        expect(described_class.for_term(term)).to include(restoration_snapshot)
        expect(described_class.for_term(term)).not_to include(other_snapshot)
      end
    end

    describe ".for_user" do
      let(:other_user) { create(:user) }
      let!(:other_user_snapshot) do
        described_class.create!(user: other_user, term: term, crn: 66666, snapshot_created_at: Time.current)
      end

      it "returns only snapshots for the given user" do
        expect(described_class.for_user(user)).to include(restoration_snapshot)
        expect(described_class.for_user(user)).not_to include(other_user_snapshot)
      end
    end
  end
end
