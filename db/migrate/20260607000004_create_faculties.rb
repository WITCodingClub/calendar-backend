class CreateFaculties < ActiveRecord::Migration[8.1]
  def change
    create_table :faculties do |t|
      t.string :email, null: false
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :middle_name
      t.string :display_name
      t.string :title
      t.string :department
      t.string :school
      t.string :employee_type
      t.string :phone
      t.string :office_location
      t.string :photo_url
      t.string :rmp_id
      t.jsonb :rmp_raw_data
      t.jsonb :directory_raw_data
      t.datetime :directory_last_synced_at
      t.timestamps
    end

    add_index :faculties, :email, unique: true
    add_index :faculties, :rmp_id, unique: true
    add_index :faculties, :department
    add_index :faculties, :employee_type
    add_index :faculties, :school
    add_index :faculties, :directory_last_synced_at
    add_index :faculties, :rmp_raw_data, using: :gin
    add_index :faculties, :directory_raw_data, using: :gin
  end
end
