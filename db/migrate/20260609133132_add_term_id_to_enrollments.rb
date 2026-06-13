class AddTermIdToEnrollments < ActiveRecord::Migration[8.1]
  def change
    add_reference :enrollments, :term, null: true, foreign_key: true

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE enrollments
          SET term_id = courses.term_id
          FROM courses
          WHERE enrollments.course_id = courses.id
        SQL
      end
    end

    change_column_null :enrollments, :term_id, false

    remove_index :enrollments, [:user_id, :course_id], if_exists: true
    add_index :enrollments, [:user_id, :course_id, :term_id],
              name: "index_enrollments_on_user_class_term", unique: true
  end
end
