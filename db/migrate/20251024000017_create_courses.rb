class CreateCourses < ActiveRecord::Migration[8.0]
  def change
    create_table :courses do |t|
      t.belongs_to :term, null: false, foreign_key: true
      t.integer :crn
      t.string :section_number, null: false
      t.string :subject # ex: Computer Science (COMP)
      t.integer :course_number # ex: 1000
      t.string :title
      t.integer :credit_hours
      t.string :grade_mode

      t.date :start_date
      t.date :end_date

      t.string :schedule_type, null: false

      t.vector :embedding, limit: 1536

      t.timestamps
    end

    add_index :courses, :crn, unique: true

  end
end
