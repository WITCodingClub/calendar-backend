# frozen_string_literal: true

class CreateFinalExams < ActiveRecord::Migration[8.1]
  def change
    create_table :final_exams do |t|
      t.references :course, null: false, foreign_key: true
      t.references :term, null: false, foreign_key: true
      t.date :exam_date, null: false
      t.integer :start_time, null: false
      t.integer :end_time, null: false
      t.string :location
      t.text :notes

      t.timestamps
    end

    add_index :final_exams, [:course_id, :term_id], unique: true
  end
end
