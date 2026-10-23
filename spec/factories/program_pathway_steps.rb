# frozen_string_literal: true

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
FactoryBot.define do
  factory :program_pathway_step do
    program_pathway
    degree_program
    sequence(:position)
    plan_years { 4 }
  end
end
