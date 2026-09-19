# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: final_exams
#
#  id            :bigint           not null, primary key
#  combined_crns :text
#  crn           :integer
#  end_time      :integer          not null
#  exam_date     :date             not null
#  location      :string
#  notes         :text
#  start_time    :integer          not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  course_id     :bigint
#  term_id       :bigint           not null
#
# Indexes
#
#  index_final_exams_on_course_id        (course_id)
#  index_final_exams_on_crn_and_term_id  (crn,term_id) UNIQUE
#  index_final_exams_on_term_id          (term_id)
#
# Foreign Keys
#
#  fk_rails_...  (course_id => courses.id)
#  fk_rails_...  (term_id => terms.id)
#
RSpec.describe FinalExam do
  describe "associations and validations" do
    subject { create(:final_exam) }

    it { is_expected.to belong_to(:term) }
    it { is_expected.to belong_to(:course).optional }
    it { is_expected.to have_many(:calendar_events).dependent(:nullify) }

    it { is_expected.to validate_presence_of(:crn) }
    it { is_expected.to validate_presence_of(:exam_date) }
    it { is_expected.to validate_presence_of(:start_time) }
    it { is_expected.to validate_presence_of(:end_time) }
    it do
      expect(subject).to validate_uniqueness_of(:crn)
        .scoped_to(:term_id)
        .with_message("can only have one final exam per CRN per term")
    end

    # #end_time_after_start_time is a custom cross-field validation, not a
    # one-liner (validate_numericality_of has no "relative to another
    # attribute" comparison).
  end

  describe "#combined_crns" do
    it "returns an Array when the value is an Array" do
      exam = described_class.new(crn: 11111, combined_crns: [ 11111, 22222 ])

      expect(exam.combined_crns).to eq([ 11111, 22222 ])
    end

    it "decodes a double-encoded JSON string from the backend import" do
      exam = described_class.new(crn: 11111, combined_crns: "[11111, 22222]")

      expect(exam.combined_crns).to eq([ 11111, 22222 ])
    end

    it "splits a plain string that is not JSON" do
      exam = described_class.new(crn: 11111, combined_crns: "11111, 22222")

      expect(exam.combined_crns).to eq(%w[11111 22222])
    end

    it "returns nil when the value is nil" do
      exam = described_class.new(crn: 11111, combined_crns: nil)

      expect(exam.combined_crns).to be_nil
    end
  end

  describe "#combined_crns_display" do
    it "joins a double-encoded JSON string without an error" do
      exam = described_class.new(crn: 11111, combined_crns: "[11111, 22222]")

      expect(exam.combined_crns_display).to eq("11111, 22222")
    end

    it "falls back to the crn when combined_crns is nil" do
      exam = described_class.new(crn: 11111, combined_crns: nil)

      expect(exam.combined_crns_display).to eq("11111")
    end
  end
end
