# frozen_string_literal: true

# One gradebook item. "ungraded" has nil points, which is not the same as a
# zero. The frontend does every grade calculation.
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
module Brightspace
  class GradeItem < ApplicationRecord
    include EncodedIds::HashidIdentifiable
    include Brightspace::Removable

    set_public_id_prefix :bgi, min_hash_length: 12

    GRADING_STATUSES = %w[graded ungraded excused].freeze

    belongs_to :course_offering, class_name: "Brightspace::CourseOffering", inverse_of: :grade_items
    belongs_to :grade_category, class_name: "Brightspace::GradeCategory", optional: true, inverse_of: :grade_items
    belongs_to :assignment, class_name: "Brightspace::Assignment", optional: true, inverse_of: :grade_items

    validates :source_id, presence: true, length: { maximum: 64 }, uniqueness: { scope: :course_offering_id }
    validates :name, presence: true, length: { maximum: 500 }
    validates :grading_status, inclusion: { in: GRADING_STATUSES }
    validates :points_possible, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    validates :weight, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  end
end
