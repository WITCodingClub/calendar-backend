# frozen_string_literal: true

# One program across every catalog year, such as the Computer Science B.S.
# The slug is the last part of its catalog path (`computer-science-bs`),
# which stays the same when the school or department changes. A few
# programs moved to a new path: RENAMED_SLUGS maps the old slug to the new
# one, so all their years stay on one program. What the program requires in
# one catalog year is a RequirementSet.
#
# A concentration points to the major it belongs to with parent_program.
# == Schema Information
#
# Table name: degree_programs
#
#  id                :bigint           not null, primary key
#  kind              :string           not null
#  level             :string           not null
#  name              :string           not null
#  slug              :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  parent_program_id :bigint
#
# Indexes
#
#  index_degree_programs_on_parent_program_id  (parent_program_id)
#  index_degree_programs_on_slug               (slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (parent_program_id => degree_programs.id) ON DELETE => nullify
#
class DegreeProgram < ApplicationRecord
  KINDS = {
    associate: "associate",
    bachelor: "bachelor",
    master: "master",
    minor: "minor",
    concentration: "concentration",
    certificate: "certificate",
    exploratory: "exploratory"
  }.freeze
  LEVELS = { undergraduate: "undergraduate", graduate: "graduate" }.freeze

  # Old catalog slugs of programs that moved to a new path, with the slug
  # of the newest catalog. Without this, the import makes two programs with
  # the same name, and a matcher that finds both links neither.
  # `bin/rails degree_requirements:merge_renamed` moves the stored years of
  # an old slug to the new one.
  RENAMED_SLUGS = {
    # 2019-2020 to 2021-2022, in the sciences department.
    "biological-engineering-program" => "biological-engineering-bs",
    # 2019-2020 to 2025-2026, in the mechanical engineering department.
    "aerospace-engineering-minor" => "aerospace-minor"
  }.freeze

  def self.current_slug(slug) = RENAMED_SLUGS.fetch(slug, slug)

  enum :kind, KINDS, validate: true
  enum :level, LEVELS, validate: true

  belongs_to :parent_program, class_name: "DegreeProgram", optional: true, inverse_of: :concentrations

  has_many :concentrations, class_name: "DegreeProgram", foreign_key: :parent_program_id,
                            inverse_of: :parent_program, dependent: :nullify
  has_many :requirement_sets, dependent: :destroy
  has_many :catalog_years, through: :requirement_sets
  has_many :program_pathway_steps, dependent: :restrict_with_error

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validate :parent_is_a_top_program

  def requirement_set_for(catalog_year)
    requirement_sets.find_by(catalog_year: catalog_year)
  end

  private

  # A concentration belongs to a major, never to itself or to another
  # concentration, so a walk up from any program ends after one step.
  def parent_is_a_top_program
    return if parent_program.nil?
    return if parent_program != self && parent_program.parent_program_id.nil?

    errors.add(:parent_program, "must be a program with no parent")
  end
end
