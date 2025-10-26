class CreateAcademicClasses < ActiveRecord::Migration[8.0]
  def change
    create_table :academic_classes do |t|
      t.belongs_to :term, null: false, foreign_key: true
      t.integer :crn
      t.string :section_number, null: false
      t.string :subject # ex: Computer Science (COMP)
      t.integer :course_number # ex: 1000
      t.string :title
      t.integer :credit_hours
      t.string :grade_mode

      t.integer :schedule_type, null: false # 1: Lecture (LEC), 2: Laboratory (LAB)

      t.timestamps
    end
  end
end
