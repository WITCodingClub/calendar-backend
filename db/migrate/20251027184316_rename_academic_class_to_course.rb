class RenameAcademicClassToCourse < ActiveRecord::Migration[8.1]
  def change
    safety_assured do
    rename_table :academic_classes, :courses
    end
  end
end
