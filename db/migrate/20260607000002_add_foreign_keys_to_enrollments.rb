class AddForeignKeysToEnrollments < ActiveRecord::Migration[8.1]
  def change
    add_column :enrollments, :user_id, :bigint, null: false
    add_column :enrollments, :course_id, :bigint, null: false
    add_index :enrollments, [ :user_id, :course_id ], unique: true
    add_index :enrollments, :user_id
    add_index :enrollments, :course_id
    add_foreign_key :enrollments, :users
    add_foreign_key :enrollments, :courses
  end
end
