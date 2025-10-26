class CreateFaculties < ActiveRecord::Migration[8.0]
  def change
    create_table :faculties do |t|
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :email, null: false
      t.timestamps
    end
  end
end
