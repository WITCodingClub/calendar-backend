# frozen_string_literal: true

# Issue #659: POST /api/process_courses/batch processes some terms in a
# background job. Record the processing state of each term for each user, so
# /api/user/is_processed can report a term as processed only when all of its
# courses are done, and can report a failed job to the extension.
class CreateTermProcessingStatuses < ActiveRecord::Migration[8.1]
  def change
    create_table :term_processing_statuses do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.references :term, null: false, foreign_key: true
      t.string :status, null: false
      t.string :error_code
      t.timestamps
    end

    add_index :term_processing_statuses, [ :user_id, :term_id ], unique: true
  end
end
