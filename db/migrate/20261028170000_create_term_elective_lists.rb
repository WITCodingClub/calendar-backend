# frozen_string_literal: true

# The elective lists that each school publishes for one term, as PDFs on the
# Registrar's "Technical, Major, and HSS Electives" page. One row in
# term_elective_lists is one PDF. docs/term-electives.md describes the import.
class CreateTermElectiveLists < ActiveRecord::Migration[8.1]
  def change
    create_table :term_elective_lists do |t|
      t.references :term, null: false, foreign_key: { on_delete: :cascade }
      t.string :url, null: false
      t.string :school
      t.string :title
      t.string :sha256, null: false
      t.text :body_text
      t.datetime :fetched_at, null: false
      t.timestamps
      t.index :url, unique: true
    end

    create_table :term_elective_courses do |t|
      t.references :term_elective_list, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :subject_code, null: false
      t.integer :course_number, null: false
      t.text :heading
      t.integer :position, null: false, default: 0
      t.references :catalog_course, foreign_key: { on_delete: :nullify }
      t.timestamps
      # One list can name a course under more than one heading, such as
      # MATH 4050 in several program lists of the same school.
      t.index [ :term_elective_list_id, :subject_code, :course_number, :heading ],
              unique: true, nulls_not_distinct: true, name: "idx_term_elective_courses_unique"
      t.index [ :subject_code, :course_number ]
    end
  end
end
