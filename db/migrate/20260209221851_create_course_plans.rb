# frozen_string_literal: true

class CreateCoursePlans < ActiveRecord::Migration[8.1]
  def change
    create_table :course_plans do |t|
      t.references :user, null: false, foreign_key: true
      t.references :term, null: false, foreign_key: true
      t.references :course, foreign_key: true
      t.string :planned_subject, null: false
      t.integer :planned_course_number, null: false
      t.integer :planned_crn
      t.string :status, default: "planned", null: false
      t.text :notes

      t.timestamps
    end

    add_index :course_plans, [:user_id, :term_id]
    add_index :course_plans, [:user_id, :course_id], unique: true, where: "course_id IS NOT NULL"
    add_index :course_plans, :status
  end

end
