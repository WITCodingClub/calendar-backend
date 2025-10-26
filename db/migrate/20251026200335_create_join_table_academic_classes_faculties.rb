class CreateJoinTableAcademicClassesFaculties < ActiveRecord::Migration[8.0]
  def change
    create_join_table :academic_classes, :faculties do |t|
      t.index [ :academic_class_id, :faculty_id ]
      t.index [ :faculty_id, :academic_class_id ]
    end
  end
end
