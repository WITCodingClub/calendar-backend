# frozen_string_literal: true

class CreateEnrollmentSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :enrollment_snapshots do |t|
      t.references :user, null: false, foreign_key: true
      t.references :term, null: false, foreign_key: true
      t.integer :crn, null: false
      
      # Store course details for reference
      t.string :subject
      t.integer :course_number
      t.string :title
      t.string :section_number
      t.string :schedule_type
      t.integer :credit_hours
      
      # Store faculty info
      t.jsonb :faculty_data, default: []
      
      # Metadata
      t.datetime :snapshot_created_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      t.string :snapshot_reason
      
      t.timestamps
    end
    
    add_index :enrollment_snapshots, [:user_id, :term_id, :crn], unique: true, name: 'idx_enrollment_snapshots_unique'
    add_index :enrollment_snapshots, :crn
    add_index :enrollment_snapshots, :snapshot_created_at
  end

end
