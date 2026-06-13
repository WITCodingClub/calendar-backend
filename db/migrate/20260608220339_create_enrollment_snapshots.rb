# frozen_string_literal: true

class CreateEnrollmentSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :enrollment_snapshots do |t|
      t.references :user, null: false, foreign_key: true
      t.references :term, null: false, foreign_key: true
      t.integer  :crn,                  null: false
      t.string   :subject
      t.string   :title
      t.integer  :course_number
      t.string   :section_number
      t.string   :schedule_type
      t.integer  :credit_hours
      t.jsonb    :faculty_data,         default: []
      t.string   :snapshot_reason
      t.datetime :snapshot_created_at,  null: false, default: -> { "CURRENT_TIMESTAMP" }

      t.timestamps
    end

    add_index :enrollment_snapshots, :crn
    add_index :enrollment_snapshots, :snapshot_created_at
    add_index :enrollment_snapshots, [ :user_id, :term_id, :crn ],
              name: :idx_enrollment_snapshots_unique, unique: true
  end
end
