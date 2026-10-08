# frozen_string_literal: true

# Syllabus rules that the user confirmed, and hypothetical grade scenarios.
# Both belong to the user, so later imports never change them.
class CreateBrightspaceSyllabusPreferencesAndGradeScenarios < ActiveRecord::Migration[8.1]
  def change
    create_table :brightspace_syllabus_preferences do |t|
      t.references :user, null: false, foreign_key: true
      t.references :course_offering, null: false, foreign_key: { to_table: :brightspace_course_offerings },
                                      index: { unique: true }
      t.string :source_revision, null: false
      t.jsonb :confirmed, null: false, default: {}
      t.timestamps
    end

    create_table :brightspace_grade_scenarios do |t|
      t.references :user, null: false, foreign_key: true
      t.references :course_offering, null: false, foreign_key: { to_table: :brightspace_course_offerings }
      t.string :name, null: false
      t.jsonb :scores, null: false, default: []
      t.jsonb :category_overrides
      t.timestamps
    end
  end
end
