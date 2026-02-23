# frozen_string_literal: true

require "rails_helper"

RSpec.describe RequirementCompletion do
  describe "validations" do
    subject { build(:requirement_completion) }

    it { is_expected.to validate_presence_of(:subject) }
    it { is_expected.to validate_presence_of(:course_number) }
    it { is_expected.to validate_presence_of(:source) }

    describe "course_id uniqueness" do
      let(:user) { create(:user) }
      let(:course) { create(:course, term: create(:term)) }
      let(:requirement) { create(:degree_requirement, degree_program: create(:degree_program)) }

      before { create(:requirement_completion, user: user, course: course, degree_requirement: requirement) }

      it "validates uniqueness of course_id scoped to user_id when course_id is present" do
        duplicate = build(:requirement_completion, user: user, course: course, degree_requirement: requirement)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:course_id]).to be_present
      end

      it "allows same course for different users" do
        other_user = create(:user)
        other_completion = build(:requirement_completion, user: other_user, course: course, degree_requirement: requirement)
        expect(other_completion).to be_valid
      end

      it "allows nil course_id (for transfer credits)" do
        completion1 = create(:requirement_completion, :transfer_credit, user: user)
        completion2 = build(:requirement_completion, :transfer_credit, user: user)
        expect(completion2).to be_valid
      end
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:degree_requirement) }
    it { is_expected.to belong_to(:course).optional }
    it { is_expected.to belong_to(:term).optional }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:source).backed_by_column_of_type(:string).with_values(wit: "wit", transfer: "transfer", ap: "ap", clep: "clep", ib: "ib") }
  end

  describe "scopes" do
    let!(:completed) { create(:requirement_completion, in_progress: false) }
    let!(:in_progress) { create(:requirement_completion, :in_progress) }
    let!(:met) { create(:requirement_completion, met_requirement: true) }
    let(:user) { create(:user) }
    let(:requirement) { create(:degree_requirement, degree_program: create(:degree_program)) }
    let!(:user_completion) { create(:requirement_completion, user: user) }
    let!(:requirement_completion) { create(:requirement_completion, degree_requirement: requirement) }

    describe ".completed" do
      it "returns only completed requirements" do
        expect(described_class.completed).to include(completed)
        expect(described_class.completed).not_to include(in_progress)
      end
    end

    describe ".in_progress" do
      it "returns only in-progress requirements" do
        expect(described_class.in_progress).to include(in_progress)
        expect(described_class.in_progress).not_to include(completed)
      end
    end

    describe ".by_user" do
      it "returns completions for the specified user" do
        expect(described_class.by_user(user)).to include(user_completion)
      end
    end

    describe ".by_requirement" do
      it "returns completions for the specified requirement" do
        expect(described_class.by_requirement(requirement)).to include(requirement_completion)
      end
    end

    describe ".met" do
      it "returns only completions that met the requirement" do
        expect(described_class.met).to include(met)
      end
    end
  end

  describe "#course_identifier" do
    it "returns formatted course identifier" do
      completion = create(:requirement_completion, subject: "COMP", course_number: 1000)
      expect(completion.course_identifier).to eq("COMP 1000")
    end
  end

  describe "#passing_grade?" do
    it "returns true for passing grades" do
      %w[A A- B+ B B- C+ C C- D+ D D- P S].each do |grade|
        completion = create(:requirement_completion, grade: grade)
        expect(completion.passing_grade?).to be true
      end
    end

    it "returns false for failing grades" do
      %w[F E].each do |grade|
        completion = create(:requirement_completion, grade: grade)
        expect(completion.passing_grade?).to be false
      end
    end

    it "returns true when grade is blank" do
      completion = create(:requirement_completion, grade: nil)
      expect(completion.passing_grade?).to be true
    end

    it "is case insensitive" do
      completion = create(:requirement_completion, grade: "a")
      expect(completion.passing_grade?).to be true
    end
  end
end
