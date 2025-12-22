# frozen_string_literal: true

class AddCrnToFinalExamsAndMakeCourseOptional < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # Add crn column to store the CRN directly (for orphan records without a course)
    add_column :final_exams, :crn, :integer

    # Make course_id optional (allow null) so we can create orphan records
    change_column_null :final_exams, :course_id, true

    # Remove the old unique constraint on course_id + term_id
    remove_index :final_exams, %i[course_id term_id], if_exists: true

    # Add new unique constraint on crn + term_id (one final exam per CRN per term)
    add_index :final_exams, %i[crn term_id], unique: true, algorithm: :concurrently

    # Backfill crn from existing course associations
    reversible do |dir|
      dir.up do
        safety_assured do
          execute <<-SQL.squish
            UPDATE final_exams
            SET crn = courses.crn
            FROM courses
            WHERE final_exams.course_id = courses.id
          SQL
        end
      end
    end
  end
end
