# frozen_string_literal: true

class CreateTransferCourses < ActiveRecord::Migration[8.1]
  def change
    create_table :transfer_courses do |t|
      t.references :university, null: false, foreign_key: { to_table: :transfer_universities }
      t.string :course_code, null: false
      t.string :course_title, null: false
      t.decimal :credits, precision: 5, scale: 2
      t.text :description
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :transfer_courses, [:university_id, :course_code], unique: true
    add_index :transfer_courses, :active
  end

end
