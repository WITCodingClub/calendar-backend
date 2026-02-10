# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeEvaluationSnapshotPolicy, type: :policy do
  subject(:policy) { described_class.new(user, snapshot) }

  let(:user) { create(:user) }
  let(:other_user) { create(:user) }

  # Note: This spec will fail until DegreeEvaluationSnapshot model exists
  # Created as placeholder for when Task #1 models are merged

  describe "Scope" do
    let!(:user_snapshot) { create(:degree_evaluation_snapshot, user: user) }
    let!(:other_snapshot) { create(:degree_evaluation_snapshot, user: other_user) }

    it "only returns snapshots owned by the user" do
      scope = described_class::Scope.new(user, DegreeEvaluationSnapshot).resolve

      expect(scope).to include(user_snapshot)
      expect(scope).not_to include(other_snapshot)
    end
  end

  context "when user owns the snapshot" do
    let(:snapshot) { create(:degree_evaluation_snapshot, user: user) }

    it { is_expected.to permit_action(:show) }
    it { is_expected.to permit_action(:create) }
    it { is_expected.to permit_action(:update) }
    it { is_expected.to permit_action(:destroy) }
  end

  context "when user does not own the snapshot" do
    let(:snapshot) { create(:degree_evaluation_snapshot, user: other_user) }

    it { is_expected.not_to permit_action(:show) }
    it { is_expected.not_to permit_action(:update) }
    it { is_expected.not_to permit_action(:destroy) }
  end

  context "when creating a new snapshot" do
    let(:snapshot) { build(:degree_evaluation_snapshot, user: user) }

    it "allows any authenticated user to create" do
      expect(policy).to permit_action(:create)
    end
  end
end
