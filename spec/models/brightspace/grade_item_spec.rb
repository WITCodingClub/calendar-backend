# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: brightspace_grade_items
#
#  id                 :bigint           not null, primary key
#  extra_credit       :boolean
#  feedback           :text
#  graded_at          :datetime
#  grading_status     :string           not null
#  name               :string           not null
#  points_earned      :decimal(10, 4)
#  points_possible    :decimal(10, 4)
#  removed_at         :datetime
#  weight             :decimal(8, 4)
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  assignment_id      :bigint
#  course_offering_id :bigint           not null
#  grade_category_id  :bigint
#  source_id          :string           not null
#
# Indexes
#
#  index_brightspace_grade_items_on_assignment_id       (assignment_id)
#  index_brightspace_grade_items_on_course_offering_id  (course_offering_id)
#  index_brightspace_grade_items_on_grade_category_id   (grade_category_id)
#  index_brightspace_grade_items_on_source              (course_offering_id,source_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (assignment_id => brightspace_assignments.id)
#  fk_rails_...  (course_offering_id => brightspace_course_offerings.id)
#  fk_rails_...  (grade_category_id => brightspace_grade_categories.id)
#
RSpec.describe Brightspace::GradeItem, type: :model do
  subject { create(:brightspace_grade_item) }

  it { is_expected.to belong_to(:course_offering) }
  it { is_expected.to belong_to(:grade_category).optional }
  it { is_expected.to belong_to(:assignment).optional }
  it { is_expected.to validate_presence_of(:source_id) }
  it { is_expected.to validate_length_of(:source_id).is_at_most(64) }
  it { is_expected.to validate_uniqueness_of(:source_id).scoped_to(:course_offering_id).ignoring_case_sensitivity }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_length_of(:name).is_at_most(500) }
  it { is_expected.to validate_inclusion_of(:grading_status).in_array(described_class::GRADING_STATUSES) }
  it { is_expected.to validate_numericality_of(:points_possible).is_greater_than_or_equal_to(0).allow_nil }
  it { is_expected.to validate_numericality_of(:weight).is_greater_than_or_equal_to(0).allow_nil }
end
