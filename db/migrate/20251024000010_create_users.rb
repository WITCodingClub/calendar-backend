# frozen_string_literal: true

class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :email,              null: false, default: ""
      t.integer :access_level,     null: false, default: 0
      t.string :first_name
      t.string :last_name
      t.string :calendar_token

      t.timestamps null: false
    end

    # add_index :users, :email,                unique: true
    add_index :users, :calendar_token, unique: true
  end
end
