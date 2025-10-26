class CreateTerms < ActiveRecord::Migration[8.0]
  def change
    create_table :terms do |t|

      t.string :uid, null: false # e.g., "202610 (Fall 2025) or 202620 (202620)"
      t.integer :year, null: false # e.g., 2024
      t.integer :semester, null: false # e.g., 1 for Spring, 2 for Fall, 3 for Summer

      t.timestamps
    end

    add_index :terms, [:year, :semester], unique: true

  end
end
