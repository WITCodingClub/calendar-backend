class CreateTerms < ActiveRecord::Migration[8.0]
  def change
    create_table :terms do |t|

      t.integer :uid, null: false
      t.integer :year  # e.g., 2024
      t.integer :semester # e.g., 1 for Spring, 2 for Fall, 3 for Summer

      t.timestamps
    end

    add_index :terms, [ :year, :semester ], unique: true
    add_index :terms, :uid, unique: true

  end
end
