# frozen_string_literal: true

class ValidateStudentProgramsProgramPathwayFk < ActiveRecord::Migration[8.1]
  def change
    validate_foreign_key :student_programs, :program_pathways
  end
end
