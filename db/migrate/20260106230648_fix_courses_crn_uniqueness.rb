# frozen_string_literal: true

class FixCoursesCrnUniqueness < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # Remove the unique constraint on CRN alone
    remove_index :courses, :crn, algorithm: :concurrently
    
    # Add a compound unique index on CRN + term_id
    add_index :courses, [:crn, :term_id], unique: true, name: 'index_courses_on_crn_and_term_id', algorithm: :concurrently
    
    # Keep a non-unique index on CRN for performance
    add_index :courses, :crn, algorithm: :concurrently
  end

end
