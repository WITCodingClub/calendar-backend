class AddRatingFieldsToFaculties < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :faculties, :rmp_id, :string
    add_index :faculties, :rmp_id, unique: true, algorithm: :concurrently
  end
end
