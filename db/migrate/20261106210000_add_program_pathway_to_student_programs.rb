# frozen_string_literal: true

# A planned program that a student added with a pathway (#868) links to it, so
# removing the pathway removes those rows. The foreign key is validated in
# the next migration.
class AddProgramPathwayToStudentPrograms < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_reference :student_programs, :program_pathway, index: { algorithm: :concurrently }
    add_foreign_key :student_programs, :program_pathways, on_delete: :nullify, validate: false
  end
end
