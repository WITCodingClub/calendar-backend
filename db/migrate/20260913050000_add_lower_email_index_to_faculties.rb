# frozen_string_literal: true

class AddLowerEmailIndexToFaculties < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # FacultyIngestService matches instructors on LOWER(email). The plain email
    # index cannot answer that, so every course import scanned the whole table
    # once per instructor.
    add_index :faculties, "LOWER(email)", name: "index_faculties_on_lower_email", algorithm: :concurrently
  end
end
