# frozen_string_literal: true

# The result of each finished course, from the LeopardWeb Student Grades page
# (#529). The extension sends an outcome, never the letter grade.
#
# A row belongs to the user and the course, not to the enrollment:
# Courses::Reprocessor deletes and creates enrollments, and the outcome must
# stay.
class CreateCourseOutcomes < ActiveRecord::Migration[8.1]
  def change
    create_table :course_outcomes do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :course, null: false, foreign_key: { on_delete: :cascade }
      t.string :outcome, null: false
      t.timestamps
    end

    add_index :course_outcomes, [ :user_id, :course_id ], unique: true
  end
end
