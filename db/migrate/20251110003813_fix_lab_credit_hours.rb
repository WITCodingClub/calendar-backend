class FixLabCreditHours < ActiveRecord::Migration[8.1]
  def up
    # LeopardWeb shows total course credit hours for all sections (lecture + lab)
    # Labs are typically 0-credit companion sections, so fix existing LAB courses

    # Store original values for rollback
    lab_courses = Course.where(schedule_type: "LAB").where.not(credit_hours: 0)

    say_with_time "Fixing #{lab_courses.count} lab courses with incorrect credit hours" do
      lab_courses.find_each do |course|
        # Store original value in a temporary table for potential rollback
        safety_assured do
          execute <<-SQL
            CREATE TABLE IF NOT EXISTS lab_credit_hours_backup (
              course_id BIGINT PRIMARY KEY,
              original_credit_hours INTEGER
            )
          SQL

          execute <<-SQL
            INSERT INTO lab_credit_hours_backup (course_id, original_credit_hours)
            VALUES (#{course.id}, #{course.credit_hours})
            ON CONFLICT (course_id) DO NOTHING
          SQL
        end

        course.update_column(:credit_hours, 0)
      end
    end
  end

  def down
    say_with_time "Restoring original credit hours for lab courses" do
      # Restore original values from backup table
      safety_assured do
        execute <<-SQL
          UPDATE courses
          SET credit_hours = lab_credit_hours_backup.original_credit_hours
          FROM lab_credit_hours_backup
          WHERE courses.id = lab_credit_hours_backup.course_id
        SQL

        # Clean up backup table
        execute "DROP TABLE IF EXISTS lab_credit_hours_backup"
      end
    end
  end
end
