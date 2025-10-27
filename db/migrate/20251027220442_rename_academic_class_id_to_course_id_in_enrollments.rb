class RenameAcademicClassIdToCourseIdInEnrollments < ActiveRecord::Migration[8.1]
  def change
    safety_assured do
      # Rename the foreign key column
      rename_column :enrollments, :academic_class_id, :course_id

      # Note: We're leaving the index names as-is since they still work correctly
      # The indexes will continue to reference the column by its new name
    end
  end
end
