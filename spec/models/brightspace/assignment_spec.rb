# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: brightspace_assignments
#
#  id                 :bigint           not null, primary key
#  closes_at          :datetime
#  description        :text
#  due_at             :datetime
#  feedback           :text
#  kind               :string           not null
#  opens_at           :datetime
#  removed_at         :datetime
#  source_url         :string
#  submission_status  :string
#  submitted_at       :datetime
#  title              :string           not null
#  user_due_at        :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  course_offering_id :bigint           not null
#  source_id          :string           not null
#
# Indexes
#
#  index_brightspace_assignments_on_course_offering_id  (course_offering_id)
#  index_brightspace_assignments_on_source              (course_offering_id,kind,source_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (course_offering_id => brightspace_course_offerings.id)
#
RSpec.describe Brightspace::Assignment, type: :model do
  subject { create(:brightspace_assignment) }

  it { is_expected.to belong_to(:course_offering) }
  it { is_expected.to have_many(:grade_items).dependent(:nullify) }

  it { is_expected.to validate_inclusion_of(:kind).in_array(described_class::KINDS) }
  it { is_expected.to validate_presence_of(:source_id) }
  it { is_expected.to validate_length_of(:source_id).is_at_most(64) }
  it { is_expected.to validate_uniqueness_of(:source_id).scoped_to(:course_offering_id, :kind).ignoring_case_sensitivity }
  it { is_expected.to validate_presence_of(:title) }
  it { is_expected.to validate_length_of(:title).is_at_most(500) }
  it { is_expected.to validate_inclusion_of(:submission_status).in_array(described_class::SUBMISSION_STATUSES).allow_nil }

  describe "#brightspace_due_at" do
    it "prefers the individual deadline" do
      assignment = build(:brightspace_assignment, due_at: 1.day.from_now, user_due_at: 3.days.from_now)

      expect(assignment.brightspace_due_at).to eq(assignment.user_due_at)
    end

    it "uses the class deadline without an individual one" do
      assignment = build(:brightspace_assignment, user_due_at: nil)

      expect(assignment.brightspace_due_at).to eq(assignment.due_at)
    end
  end

  describe ".not_removed" do
    it "leaves out removed rows" do
      kept = create(:brightspace_assignment)
      create(:brightspace_assignment, :removed, course_offering: kept.course_offering)

      expect(described_class.not_removed).to contain_exactly(kept)
    end
  end
end
