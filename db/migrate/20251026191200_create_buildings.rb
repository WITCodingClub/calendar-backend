class CreateBuildings < ActiveRecord::Migration[8.0]
  def change
    create_table :buildings do |t|
      t.string :abbreviation, null: false # ex: "WENTW"
      t.string :name, null: false # ex: "Wentworth Hall"

      t.timestamps
    end

    add_index :buildings, :abbreviation, unique: true
    add_index :buildings, :name, unique: true
  end
end
