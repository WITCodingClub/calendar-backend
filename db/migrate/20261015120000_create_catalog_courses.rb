# frozen_string_literal: true

# One row for each course (subject code and number), across terms. Banner's
# description, prerequisites, corequisites, and restrictions are stored here
# (Catalog::CourseDetailsSync). course_prerequisites links each prerequisite to
# the course it names, so a course can also list what it unlocks.
class CreateCatalogCourses < ActiveRecord::Migration[8.1]
  def change
    create_table :catalog_courses do |t|
      t.string   :subject_code,  null: false
      t.integer  :course_number, null: false
      t.string   :title
      t.text     :description
      t.integer  :credit_hours
      # The terms in Banner's "(4 credits) fall, spring" tail: fall, spring, summer.
      t.string   :typically_offered, array: true, null: false, default: []
      t.jsonb    :prerequisites
      t.jsonb    :corequisites,  null: false, default: []
      t.jsonb    :restrictions,  null: false, default: []
      t.references :source_term, foreign_key: { to_table: :terms }
      t.datetime :details_fetched_at
      t.timestamps

      t.index [ :subject_code, :course_number ], unique: true
    end

    create_table :course_prerequisites do |t|
      t.references :catalog_course, null: false, foreign_key: { on_delete: :cascade }
      t.references :required_catalog_course, foreign_key: { to_table: :catalog_courses, on_delete: :nullify }
      t.string  :required_subject_code,  null: false
      t.integer :required_course_number, null: false
      t.string  :min_grade
      t.timestamps

      t.index [ :required_subject_code, :required_course_number ]
    end
  end
end
