# frozen_string_literal: true

# The result of each finished course, from the LeopardWeb Student Grades page
# (#529). The extension sends an outcome, never the letter grade.
#
# A row names the course by term code and CRN, not by course id:
# Courses::Reprocessor deletes and creates enrollments, and
# `rake catalog:refresh` deletes and imports the courses of a term again. The
# outcome must stay through both.
class CreateCourseOutcomes < ActiveRecord::Migration[8.1]
  def change
    create_table :course_outcomes do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.integer :term_uid, null: false
      t.integer :crn, null: false
      t.string :outcome, null: false
      t.timestamps
    end

    add_index :course_outcomes, [ :user_id, :term_uid, :crn ], unique: true
  end
end
