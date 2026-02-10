# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserDegreeProgram do
  describe "validations" do
    subject { build(:user_degree_program) }

    it { is_expected.to validate_presence_of(:program_type) }
    it { is_expected.to validate_presence_of(:catalog_year) }
    it { is_expected.to validate_presence_of(:status) }

    it { is_expected.to validate_numericality_of(:catalog_year).only_integer.is_greater_than(2000) }

    describe "degree_program_id uniqueness" do
      let(:user) { create(:user) }
      let(:degree_program) { create(:degree_program) }

      before { create(:user_degree_program, user: user, degree_program: degree_program) }

      it "validates uniqueness of degree_program_id scoped to user_id" do
        duplicate = build(:user_degree_program, user: user, degree_program: degree_program)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:degree_program_id]).to be_present
      end
    end

    describe "only one primary per user" do
      let(:user) { create(:user) }

      before { create(:user_degree_program, :primary, user: user) }

      it "prevents multiple primary programs for the same user" do
        duplicate_primary = build(:user_degree_program, :primary, user: user)
        expect(duplicate_primary).not_to be_valid
        expect(duplicate_primary.errors[:primary]).to include("user can only have one primary degree program")
      end

      it "allows primary program for a different user" do
        other_user = create(:user)
        other_primary = build(:user_degree_program, :primary, user: other_user)
        expect(other_primary).to be_valid
      end
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:degree_program) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:status).with_values(active: "active", completed: "completed", dropped: "dropped", suspended: "suspended").with_default(:active) }
    it { is_expected.to define_enum_for(:program_type).with_values(major: "major", minor: "minor", certificate: "certificate", concentration: "concentration") }
  end

  describe "scopes" do
    let!(:active_program) { create(:user_degree_program, status: :active) }
    let!(:completed_program) { create(:user_degree_program, :completed) }
    let!(:primary_program) { create(:user_degree_program, :primary) }
    let!(:minor_program) { create(:user_degree_program, :minor) }

    describe ".active" do
      it "returns only active programs" do
        expect(described_class.active).to include(active_program)
        expect(described_class.active).not_to include(completed_program)
      end
    end

    describe ".primary" do
      it "returns only primary programs" do
        expect(described_class.primary).to include(primary_program)
        expect(described_class.primary).not_to include(active_program)
      end
    end

    describe ".by_type" do
      it "returns programs of the specified type" do
        expect(described_class.by_type("minor")).to include(minor_program)
        expect(described_class.by_type("minor")).not_to include(primary_program)
      end
    end
  end
end
