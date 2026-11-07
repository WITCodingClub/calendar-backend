# frozen_string_literal: true

# A path through more than one program. The steps name the programs in order.
#
# - combined: a fixed list of programs from the catalog's Accelerated
#   Programs page, such as the 5-year Architecture B.S. plus M.Arch.
# - double_leopard: a 3+1 or 4+1 master's. The steps are the master's
#   programs only, because a senior in any bachelor's program can apply. The
#   student's own bachelor's is the first part, and its plan (3 or 4 years)
#   makes it a 3+1 or a 4+1.
#
# max_shared_courses and max_shared_credits are how much of one program can
# also count toward the next: Double Leopard students take up to two
# graduate courses in their senior year.
#
# DegreeRequirements::PathwaySync fills the rows from the catalog and wit.edu.
# == Schema Information
#
# Table name: program_pathways
#
#  id                 :bigint           not null, primary key
#  active             :boolean          default(TRUE), not null
#  kind               :string           not null
#  max_shared_courses :integer
#  max_shared_credits :integer
#  name               :string           not null
#  slug               :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
# Indexes
#
#  index_program_pathways_on_slug  (slug) UNIQUE
#
class ProgramPathway < ApplicationRecord
  KINDS = { combined: "combined", double_leopard: "double_leopard" }.freeze

  enum :kind, KINDS, validate: true

  has_many :steps, -> { order(:position) }, class_name: "ProgramPathwayStep", dependent: :delete_all,
                                             inverse_of: :program_pathway
  has_many :degree_programs, through: :steps
  # The planned programs a student added with this pathway (#868). The
  # database sets the link to null when the pathway is deleted.
  has_many :student_programs, dependent: nil

  scope :active, -> { where(active: true) }

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :max_shared_courses, :max_shared_credits,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
end
