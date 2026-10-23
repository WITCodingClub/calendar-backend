# frozen_string_literal: true

# One plan of study on a program page: the courses for each semester, such
# as the "Four Year Program" or the "Three Year Program" of the Computer
# Science B.S. years is the length of the plan, which course planning needs
# to map each semester of the plan to a term.
# == Schema Information
#
# Table name: program_plans
#
#  id                 :bigint           not null, primary key
#  accelerated        :boolean          default(FALSE), not null
#  name               :string           not null
#  position           :integer          default(0), not null
#  total_credits      :integer
#  years              :integer          not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  requirement_set_id :bigint           not null
#
# Indexes
#
#  index_program_plans_on_requirement_set_id_and_position  (requirement_set_id,position) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (requirement_set_id => requirement_sets.id) ON DELETE => cascade
#
class ProgramPlan < ApplicationRecord
  belongs_to :requirement_set

  has_many :items, -> { order(:position) }, class_name: "ProgramPlanItem", dependent: :delete_all,
                                             inverse_of: :program_plan
  # The elective lists printed under this plan. Lists that the page prints
  # once for every plan belong to the requirement set only.
  has_many :elective_groups, dependent: :delete_all

  validates :name, presence: true
  validates :years, presence: true, numericality: { only_integer: true, in: 1..6 }
  validates :position, uniqueness: { scope: :requirement_set_id }
end
