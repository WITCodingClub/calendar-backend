# frozen_string_literal: true

class AddDirectoryFieldsToFaculties < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # Core directory fields
    add_column :faculties, :title, :string
    add_column :faculties, :phone, :string
    add_column :faculties, :office_location, :string
    add_column :faculties, :department, :string
    add_column :faculties, :school, :string
    add_column :faculties, :photo_url, :string
    add_column :faculties, :employee_type, :string

    # Handle middle names properly (fixes name display issues)
    add_column :faculties, :middle_name, :string
    add_column :faculties, :display_name, :string

    # Raw directory data for future reference
    add_column :faculties, :directory_raw_data, :jsonb, default: {}

    # Sync tracking
    add_column :faculties, :directory_last_synced_at, :datetime

    # Indexes for common queries
    add_index :faculties, :department, algorithm: :concurrently, if_not_exists: true
    add_index :faculties, :school, algorithm: :concurrently, if_not_exists: true
    add_index :faculties, :employee_type, algorithm: :concurrently, if_not_exists: true
    add_index :faculties, :directory_last_synced_at, algorithm: :concurrently, if_not_exists: true
    add_index :faculties, :directory_raw_data, using: :gin, algorithm: :concurrently, if_not_exists: true
  end
end
