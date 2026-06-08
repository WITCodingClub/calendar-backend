class CreateFinalExams < ActiveRecord::Migration[8.1]
  def change
    create_table :final_exams do |t|
      t.references :term, null: false, foreign_key: true
      t.references :course, foreign_key: true
      t.integer :crn
      t.date :exam_date, null: false
      t.integer :start_time, null: false
      t.integer :end_time, null: false
      t.string :location
      t.text :notes
      t.text :combined_crns
      t.timestamps
    end

    add_index :final_exams, [ :crn, :term_id ], unique: true
  end
end
