# frozen_string_literal: true

require "rails_helper"

RSpec.describe TermProcessingStatus do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:term) }
  end

  describe "validations" do
    subject { create(:term_processing_status) }

    it { is_expected.to validate_uniqueness_of(:term_id).scoped_to(:user_id) }

    it do
      expect(subject).to define_enum_for(:status)
        .with_values(pending: "pending", processing: "processing", processed: "processed", failed: "failed")
        .backed_by_column_of_type(:string)
        .validating
    end

    it { is_expected.to validate_inclusion_of(:error_code).in_array(TermProcessingStatus::ERROR_CODES.values).allow_nil }
  end

  describe ".record!" do
    let(:user) { create(:user) }
    let(:term) { create(:term) }

    it "creates the row for a new term" do
      described_class.record!(user, term, :processing)

      expect(described_class.find_by(user: user, term: term)).to have_attributes(status: "processing", error_code: nil)
    end

    it "updates the row and clears an old error code" do
      create(:term_processing_status, :failed, user: user, term: term)

      described_class.record!(user, term, :pending)

      expect(described_class.where(user: user, term: term).sole).to have_attributes(status: "pending", error_code: nil)
    end

    it "stores the error code of a failed term" do
      described_class.record!(user, term, :failed, error_code: :term_not_found)

      expect(described_class.find_by(user: user, term: term)).to have_attributes(status: "failed", error_code: "term_not_found")
    end

    it "rejects an unknown status" do
      expect { described_class.record!(user, term, :done) }.to raise_error(KeyError)
    end
  end
end
