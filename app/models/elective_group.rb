# frozen_string_literal: true

# One elective list on a program page, such as "Computer Science Electives,
# select four (4) courses from the following list". heading is the text as
# printed. min_courses and min_credits are read from it, and are nil when
# the import could not read a number.
#
# A list printed under one plan has a program_plan. A list printed once for
# the whole program has none.
# == Schema Information
#
# Table name: elective_groups
#
#  id                 :bigint           not null, primary key
#  heading            :text
#  min_courses        :integer
#  min_credits        :integer
#  name               :string           not null
#  notes              :text
#  position           :integer          default(0), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  program_plan_id    :bigint
#  requirement_set_id :bigint           not null
#
# Indexes
#
#  idx_elective_groups_unique                (requirement_set_id,program_plan_id,position) UNIQUE NULLS NOT DISTINCT
#  index_elective_groups_on_program_plan_id  (program_plan_id)
#
# Foreign Keys
#
#  fk_rails_...  (program_plan_id => program_plans.id) ON DELETE => cascade
#  fk_rails_...  (requirement_set_id => requirement_sets.id) ON DELETE => cascade
#
class ElectiveGroup < ApplicationRecord
  belongs_to :requirement_set
  belongs_to :program_plan, optional: true

  has_many :courses, -> { order(:position) }, class_name: "ElectiveGroupCourse", dependent: :delete_all,
                                               inverse_of: :elective_group
  has_many :program_plan_items, dependent: :nullify

  validates :name, presence: true
  validates :position, uniqueness: { scope: [ :requirement_set_id, :program_plan_id ] }
  validates :min_courses, :min_credits, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :plan_in_same_requirement_set

  private

  def plan_in_same_requirement_set
    return if program_plan.nil? || program_plan.requirement_set_id == requirement_set_id

    errors.add(:program_plan, "must belong to the same requirement set")
  end
end
