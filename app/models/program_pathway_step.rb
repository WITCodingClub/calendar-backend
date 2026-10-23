# frozen_string_literal: true

# One program in a ProgramPathway. plan_years is the length of the plan the
# student follows in this program, such as 3 for the three-year B.S. of a
# 3+1. It names no catalog year, because each program a student takes has
# its own catalog year.
# == Schema Information
#
# Table name: program_pathway_steps
#
#  id                 :bigint           not null, primary key
#  plan_years         :integer
#  position           :integer          not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  degree_program_id  :bigint           not null
#  program_pathway_id :bigint           not null
#
# Indexes
#
#  index_program_pathway_steps_on_degree_program_id                (degree_program_id)
#  index_program_pathway_steps_on_program_pathway_id_and_position  (program_pathway_id,position) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (degree_program_id => degree_programs.id)
#  fk_rails_...  (program_pathway_id => program_pathways.id) ON DELETE => cascade
#
class ProgramPathwayStep < ApplicationRecord
  belongs_to :program_pathway
  belongs_to :degree_program

  validates :position, presence: true, uniqueness: { scope: :program_pathway_id }
  validates :plan_years, numericality: { only_integer: true, in: 1..6 }, allow_nil: true
end
