class CreateCoursesFacultiesJoinTable < ActiveRecord::Migration[8.1]
  def change
    create_join_table :courses, :faculties do |t|
      t.index :course_id
      t.index :faculty_id
      t.index [ :course_id, :faculty_id ], unique: true
    end
  end
end
