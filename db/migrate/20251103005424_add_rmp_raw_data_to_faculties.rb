class AddRmpRawDataToFaculties < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :faculties, :rmp_raw_data, :jsonb, default: {}
    add_index :faculties, :rmp_raw_data, using: :gin, algorithm: :concurrently
  end
end
