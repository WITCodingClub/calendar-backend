class CreateEnrollments < ActiveRecord::Migration[8.1]
  def change
    create_table :enrollments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :course, null: false, foreign_key: true
      t.references :term, null: false, foreign_key: true

      t.timestamps
    end

    add_index :enrollments, [
      :user_id, :course_id, :term_id
    ], unique: true, name: "index_enrollments_on_user_class_term"
  end
end
