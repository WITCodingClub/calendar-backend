class CreateBuildings < ActiveRecord::Migration[8.0]
  def change
    create_table :buildings do |t|
      t.string :abbreviation, null: false # ex: "WENTW"
      t.string :name, null: false # ex: "Wentworth Hall"

      t.timestamps
    end
  end
end
