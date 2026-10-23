# frozen_string_literal: true

# The course descriptions as printed in each catalog year, and the old
# course codes that a later code replaced (COMP128 became COMP1000 in
# 2015-2016). Plans in the old catalogs name the old codes (#526).
class CreateCatalogYearCoursesAndCourseCodeAliases < ActiveRecord::Migration[8.1]
  def change
    create_table :catalog_year_courses do |t|
      t.references :catalog_year, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :subject_code, null: false
      t.integer :course_number, null: false
      t.references :catalog_course, foreign_key: { on_delete: :nullify }
      t.string :title
      t.text :description
      t.integer :min_credits
      t.integer :max_credits
      t.text :prerequisite_text
      t.string :typically_offered, array: true, null: false, default: []
      t.timestamps
      t.index [ :catalog_year_id, :subject_code, :course_number ], unique: true,
                                                                   name: "idx_catalog_year_courses_unique"
      t.index [ :subject_code, :course_number ]
    end

    create_table :course_code_aliases do |t|
      t.string :from_subject_code, null: false
      t.integer :from_course_number, null: false
      t.string :to_subject_code, null: false
      t.integer :to_course_number, null: false
      t.string :source, null: false
      t.datetime :reviewed_at
      t.string :note
      t.timestamps
      t.index [ :from_subject_code, :from_course_number, :to_subject_code, :to_course_number ],
              unique: true, name: "idx_course_code_aliases_unique"
      t.index [ :to_subject_code, :to_course_number ]
    end
  end
end
