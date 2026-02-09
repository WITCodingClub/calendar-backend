# frozen_string_literal: true

class CreateTransferUniversities < ActiveRecord::Migration[8.1]
  def change
    create_table :transfer_universities do |t|
      t.string :name, null: false
      t.string :code, null: false
      t.string :state
      t.string :country
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :transfer_universities, :code, unique: true
    add_index :transfer_universities, :name
    add_index :transfer_universities, :active
  end

end
