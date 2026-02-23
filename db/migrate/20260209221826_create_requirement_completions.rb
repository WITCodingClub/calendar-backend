# frozen_string_literal: true

class CreateRequirementCompletions < ActiveRecord::Migration[8.1]
  def change
    create_table :requirement_completions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :degree_requirement, null: false, foreign_key: true
      t.references :course, foreign_key: true
      t.references :term, foreign_key: true
      t.string :subject, null: false
      t.integer :course_number, null: false
      t.string :course_title
      t.decimal :credits, precision: 5, scale: 2
      t.string :grade
      t.string :source, null: false
      t.datetime :completed_at
      t.boolean :in_progress, default: false, null: false
      t.boolean :met_requirement, default: false, null: false

      t.timestamps
    end

    add_index :requirement_completions, [:user_id, :degree_requirement_id]
    add_index :requirement_completions, [:user_id, :course_id], unique: true, where: "course_id IS NOT NULL"
    add_index :requirement_completions, :source
    add_index :requirement_completions, :in_progress
  end

end
