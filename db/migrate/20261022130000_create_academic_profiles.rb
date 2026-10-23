# frozen_string_literal: true

# The academic profile that the extension reads from the LeopardWeb Student
# Profile page (#529): one academic_profiles row per user, and one
# student_programs row for each major, minor, concentration, or certificate.
#
# The values are stored as LeopardWeb shows them. A later migration links each
# student program to degree_programs and catalog_years (#526) when those tables
# exist. Terms are Banner term codes, not term ids: a catalog term can be older
# than the first term in the terms table.
class CreateAcademicProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :academic_profiles do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :level
      t.string :class_standing
      t.string :admit_type
      t.integer :admit_term_uid
      t.string :leopardweb_digest
      t.datetime :leopardweb_synced_at
      t.timestamps
    end

    create_table :student_programs do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :role, null: false
      t.string :code
      t.string :name, null: false
      t.string :degree
      t.string :college
      t.string :department
      t.string :concentration
      t.string :study_path
      t.integer :catalog_term_uid
      t.string :status, null: false, default: "active"
      t.datetime :ended_at
      t.string :source, null: false
      t.timestamps
    end

    add_index :student_programs, [ :user_id, :status ]
  end
end
