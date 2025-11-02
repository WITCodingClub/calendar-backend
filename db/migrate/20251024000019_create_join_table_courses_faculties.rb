class CreateJoinTableCoursesFaculties < ActiveRecord::Migration[8.0]
  def change
    create_join_table :courses, :faculties do |t|
      t.index [ :course_id, :faculty_id ]
      t.index [ :faculty_id, :course_id ]
    end
  end
end
