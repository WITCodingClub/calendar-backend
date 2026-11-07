# frozen_string_literal: true

# What a major adds to the humanities and social science requirement: the
# credit total, and the categories it asks one course of (Humanities, Social
# Sciences, Ethics, directed courses). DegreeRequirements::HssNoteParser
# reads it from the program page. nil for a set from a PDF.
class AddHssRequirementToRequirementSets < ActiveRecord::Migration[8.1]
  def change
    add_column :requirement_sets, :hss_requirement, :jsonb
  end
end
