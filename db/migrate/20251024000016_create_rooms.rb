class CreateRooms < ActiveRecord::Migration[8.0]
  def change
    create_table :rooms do |t|
      t.integer :number

      t.belongs_to :building, null: false, foreign_key: true

      t.timestamps
    end
  end
end
