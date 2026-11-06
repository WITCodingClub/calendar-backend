# frozen_string_literal: true

# == Schema Information
#
# Table name: student_programs
#
#  id                 :bigint           not null, primary key
#  catalog_term_uid   :integer
#  code               :string
#  college            :string
#  concentration      :string
#  degree             :string
#  department         :string
#  ended_at           :datetime
#  name               :string           not null
#  role               :string           not null
#  source             :string           not null
#  status             :string           default("active"), not null
#  study_path         :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  catalog_year_id    :bigint
#  degree_program_id  :bigint
#  program_pathway_id :bigint
#  user_id            :bigint           not null
#
# Indexes
#
#  index_student_programs_on_catalog_year_id     (catalog_year_id)
#  index_student_programs_on_degree_program_id   (degree_program_id)
#  index_student_programs_on_program_pathway_id  (program_pathway_id)
#  index_student_programs_on_user_id_and_status  (user_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_year_id => catalog_years.id) ON DELETE => nullify
#  fk_rails_...  (degree_program_id => degree_programs.id) ON DELETE => nullify
#  fk_rails_...  (program_pathway_id => program_pathways.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
# One major, minor, concentration, or certificate of a student, as LeopardWeb
# shows it (#529). catalog_term_uid is the Banner code of the catalog term.
#
# A row from LeopardWeb is never deleted. When a program leaves the student's
# list, AcademicProfiles::Sync ends the row, so a change of major keeps the
# old major. AcademicProfiles::ProgramMatcher sets degree_program and
# catalog_year when the degree catalog has them.
#
# A planned row is a program the student thinks about taking, such as a
# minor (#868). The student adds it from the degree catalog, so it always has
# a degree_program and a catalog_year, and no catalog_term_uid. Sync and
# ProgramMatcher read only active rows, so they never change a planned row.
# AcademicProfiles::PlannedPrograms adds and removes planned rows, one
# program at a time or all the programs of a ProgramPathway.
class StudentProgram < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :spr

  ROLES = { major: "major", minor: "minor", concentration: "concentration", certificate: "certificate" }.freeze
  STATUSES = { active: "active", ended: "ended", planned: "planned" }.freeze
  SOURCES = { leopardweb: "leopardweb", student: "student" }.freeze

  enum :role, ROLES, validate: true
  enum :status, STATUSES, validate: true
  enum :source, SOURCES, validate: true, prefix: true

  belongs_to :user
  belongs_to :degree_program, optional: true
  belongs_to :catalog_year, optional: true
  # Set on a planned row that the student added with a pathway, such as a
  # 4+1. Removing the pathway removes its rows.
  belongs_to :program_pathway, optional: true

  validates :name, presence: true
  validates :degree_program, :catalog_year, presence: true, if: :planned?

  def catalog_term = AcademicProfiles::TermCode.label(catalog_term_uid)

  # "2025-2026". A LeopardWeb row does not need a CatalogYear row. A planned
  # row has no catalog term, so its name comes from its CatalogYear.
  def catalog_year_name = AcademicProfiles::TermCode.catalog_year(catalog_term_uid) || catalog_year&.name

  # true when the program links to the degree catalog. false when its catalog
  # year is imported and has no such program. nil when the catalog year is
  # not imported yet, so no answer is known.
  def matched?
    return true if degree_program_id
    return false if catalog_year&.imported?

    nil
  end
end
