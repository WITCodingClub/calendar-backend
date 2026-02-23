# frozen_string_literal: true

class CreateCoursePrerequisites < ActiveRecord::Migration[8.1]
  def change
    create_table :course_prerequisites do |t|
      t.references :course, null: false, foreign_key: true
      t.string :prerequisite_type, null: false
      t.text :prerequisite_rule, null: false
      t.string :prerequisite_logic
      t.string :min_grade
      t.boolean :waivable, default: false, null: false

      t.timestamps
    end

    add_index :course_prerequisites, :prerequisite_type
    add_index :course_prerequisites, [:course_id, :prerequisite_type]
  end

end
