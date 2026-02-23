# frozen_string_literal: true

require "rails_helper"

RSpec.describe CoursePlan do
  describe "validations" do
    subject { build(:course_plan) }

    it { is_expected.to validate_presence_of(:planned_subject) }
    it { is_expected.to validate_presence_of(:planned_course_number) }
    it { is_expected.to validate_presence_of(:status) }

    describe "course_id uniqueness" do
      let(:user) { create(:user) }
      let(:course) { create(:course, term: create(:term)) }
      let(:term) { create(:term) }

      before { create(:course_plan, user: user, course: course, term: term) }

      it "validates uniqueness of course_id scoped to user_id when course_id is present" do
        duplicate = build(:course_plan, user: user, course: course, term: term)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:course_id]).to be_present
      end

      it "allows same course for different users" do
        other_user = create(:user)
        other_plan = build(:course_plan, user: other_user, course: course, term: term)
        expect(other_plan).to be_valid
      end

      it "allows nil course_id" do
        plan1 = create(:course_plan, user: user, course: nil, term: term)
        plan2 = build(:course_plan, user: user, course: nil, term: term)
        expect(plan2).to be_valid
      end
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:term) }
    it { is_expected.to belong_to(:course).optional }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:status).backed_by_column_of_type(:string).with_values(planned: "planned", enrolled: "enrolled", completed: "completed", dropped: "dropped", cancelled: "cancelled").with_default(:planned) }
  end

  describe "scopes" do
    let(:user) { create(:user) }
    let(:term) { create(:term) }
    let!(:planned) { create(:course_plan, user: user, term: term, status: :planned) }
    let!(:enrolled) { create(:course_plan, :enrolled, user: user, term: term) }
    let!(:completed) { create(:course_plan, :completed) }

    describe ".active" do
      it "returns only planned and enrolled plans" do
        expect(described_class.active).to include(planned, enrolled)
        expect(described_class.active).not_to include(completed)
      end
    end

    describe ".by_user" do
      it "returns plans for the specified user" do
        expect(described_class.by_user(user)).to include(planned, enrolled)
        expect(described_class.by_user(user)).not_to include(completed)
      end
    end

    describe ".by_term" do
      it "returns plans for the specified term" do
        expect(described_class.by_term(term)).to include(planned, enrolled)
        expect(described_class.by_term(term)).not_to include(completed)
      end
    end

    describe ".by_status" do
      it "returns plans with the specified status" do
        expect(described_class.by_status(:planned)).to include(planned)
        expect(described_class.by_status(:planned)).not_to include(enrolled)
      end
    end
  end

  describe "#course_identifier" do
    it "returns formatted course identifier" do
      plan = create(:course_plan, planned_subject: "COMP", planned_course_number: 2000)
      expect(plan.course_identifier).to eq("COMP 2000")
    end
  end

  describe ".total_credits_for_term" do
    let(:user) { create(:user) }
    let(:term) { create(:term) }
    let(:course1) { create(:course, term: term, credit_hours: 3) }
    let(:course2) { create(:course, term: term, credit_hours: 4) }

    before do
      create(:course_plan, user: user, term: term, course: course1, status: :planned)
      create(:course_plan, user: user, term: term, course: course2, status: :enrolled)
      create(:course_plan, user: user, term: term, status: :dropped) # should not count
    end

    it "calculates total credits for active plans in a term" do
      expect(described_class.total_credits_for_term(user, term)).to eq(7)
    end
  end

  describe "#enrolled?" do
    it "returns true when status is enrolled" do
      plan = create(:course_plan, :enrolled)
      expect(plan.enrolled?).to be true
    end

    it "returns true when planned_crn is present" do
      plan = create(:course_plan, planned_crn: 12345, status: :planned)
      expect(plan.enrolled?).to be true
    end

    it "returns false when no CRN and status is not enrolled" do
      plan = create(:course_plan, planned_crn: nil, status: :planned)
      expect(plan.enrolled?).to be false
    end
  end
end
