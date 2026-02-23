# frozen_string_literal: true

# == Schema Information
#
# Table name: degree_evaluation_snapshots
# Database name: primary
#
#  id                      :bigint           not null, primary key
#  content_hash            :string
#  evaluated_at            :datetime         not null
#  evaluation_met          :boolean          default(FALSE), not null
#  minimum_gpa             :decimal(3, 2)
#  overall_gpa             :decimal(3, 2)
#  parsed_data             :jsonb
#  raw_html                :text
#  total_credits_completed :decimal(5, 2)
#  total_credits_required  :decimal(5, 2)
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  degree_program_id       :bigint           not null
#  evaluation_term_id      :bigint           not null
#  user_id                 :bigint           not null
#
# Indexes
#
#  idx_degree_eval_snapshots_unique                               (user_id,degree_program_id,evaluation_term_id) UNIQUE
#  index_degree_evaluation_snapshots_on_content_hash              (content_hash)
#  index_degree_evaluation_snapshots_on_degree_program_id         (degree_program_id)
#  index_degree_evaluation_snapshots_on_evaluated_at              (evaluated_at)
#  index_degree_evaluation_snapshots_on_evaluation_term_id        (evaluation_term_id)
#  index_degree_evaluation_snapshots_on_user_id                   (user_id)
#  index_degree_evaluation_snapshots_on_user_id_and_evaluated_at  (user_id,evaluated_at)
#
# Foreign Keys
#
#  fk_rails_...  (degree_program_id => degree_programs.id)
#  fk_rails_...  (evaluation_term_id => terms.id)
#  fk_rails_...  (user_id => users.id)
#
require "rails_helper"

RSpec.describe DegreeEvaluationSnapshot do
  describe "validations" do
    subject { build(:degree_evaluation_snapshot) }

    it { is_expected.to validate_presence_of(:evaluated_at) }

    describe "evaluation_term_id uniqueness" do
      let(:user) { create(:user) }
      let(:degree_program) { create(:degree_program) }
      let(:term) { create(:term) }

      before { create(:degree_evaluation_snapshot, user: user, degree_program: degree_program, evaluation_term: term) }

      it "validates uniqueness of evaluation_term_id scoped to user_id and degree_program_id" do
        duplicate = build(:degree_evaluation_snapshot, user: user, degree_program: degree_program, evaluation_term: term)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:evaluation_term_id]).to be_present
      end
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:degree_program) }
    it { is_expected.to belong_to(:evaluation_term).class_name("Term") }
  end

  describe "scopes" do
    let(:user) { create(:user) }
    let(:program) { create(:degree_program) }
    let!(:old_snapshot) { create(:degree_evaluation_snapshot, user: user, evaluated_at: 1.month.ago) }
    let!(:met_snapshot) { create(:degree_evaluation_snapshot, :completed, evaluated_at: 1.week.ago) }
    let!(:recent_snapshot) { create(:degree_evaluation_snapshot, user: user, degree_program: program, evaluated_at: 1.day.ago) }

    describe ".most_recent" do
      it "returns snapshots ordered by evaluated_at descending" do
        expect(described_class.most_recent.first).to eq(recent_snapshot)
      end
    end

    describe ".by_user" do
      it "returns snapshots for the specified user" do
        expect(described_class.by_user(user)).to include(recent_snapshot, old_snapshot)
        expect(described_class.by_user(user)).not_to include(met_snapshot)
      end
    end

    describe ".by_program" do
      it "returns snapshots for the specified program" do
        expect(described_class.by_program(program)).to include(recent_snapshot)
      end
    end

    describe ".evaluation_met" do
      it "returns only snapshots where evaluation was met" do
        expect(described_class.evaluation_met).to include(met_snapshot)
        expect(described_class.evaluation_met).not_to include(recent_snapshot)
      end
    end
  end

  describe ".latest_for_user_and_program" do
    let(:user) { create(:user) }
    let(:program) { create(:degree_program) }
    let!(:old_snapshot) { create(:degree_evaluation_snapshot, user: user, degree_program: program, evaluated_at: 1.month.ago) }
    let!(:recent_snapshot) { create(:degree_evaluation_snapshot, user: user, degree_program: program, evaluated_at: 1.day.ago) }

    it "returns the most recent snapshot for the user and program" do
      expect(described_class.latest_for_user_and_program(user, program)).to eq(recent_snapshot)
    end
  end

  describe "#progress_percentage" do
    it "calculates the percentage of credits completed" do
      snapshot = create(:degree_evaluation_snapshot, total_credits_required: 120.0, total_credits_completed: 90.0)
      expect(snapshot.progress_percentage).to eq(75.0)
    end

    it "returns 0 when total_credits_required is nil" do
      snapshot = create(:degree_evaluation_snapshot, total_credits_required: nil, total_credits_completed: 90.0)
      expect(snapshot.progress_percentage).to eq(0)
    end

    it "returns 0 when total_credits_required is zero" do
      snapshot = create(:degree_evaluation_snapshot, total_credits_required: 0, total_credits_completed: 90.0)
      expect(snapshot.progress_percentage).to eq(0)
    end
  end

  describe "#gpa_requirement_met?" do
    it "returns true when overall GPA meets minimum" do
      snapshot = create(:degree_evaluation_snapshot, overall_gpa: 3.5, minimum_gpa: 2.0)
      expect(snapshot.gpa_requirement_met?).to be true
    end

    it "returns false when overall GPA is below minimum" do
      snapshot = create(:degree_evaluation_snapshot, :below_gpa)
      expect(snapshot.gpa_requirement_met?).to be false
    end

    it "returns true when minimum_gpa is nil" do
      snapshot = create(:degree_evaluation_snapshot, overall_gpa: 2.5, minimum_gpa: nil)
      expect(snapshot.gpa_requirement_met?).to be true
    end

    it "returns false when overall_gpa is nil" do
      snapshot = create(:degree_evaluation_snapshot, overall_gpa: nil, minimum_gpa: 2.0)
      expect(snapshot.gpa_requirement_met?).to be false
    end
  end
end
