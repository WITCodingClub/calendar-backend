# frozen_string_literal: true

class FixCoursesCrnUniqueness < ActiveRecord::Migration[8.1]
  def change
    # Remove the unique constraint on CRN alone
    remove_index :courses, :crn
    
    # Add a compound unique index on CRN + term_id
    add_index :courses, [:crn, :term_id], unique: true, name: 'index_courses_on_crn_and_term_id'
    
    # Keep a non-unique index on CRN for performance
    add_index :courses, :crn
  end

end
