class CreateRatingDistributions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    create_table :rating_distributions do |t|
      t.bigint :faculty_id, null: false
      t.integer :r1, default: 0
      t.integer :r2, default: 0
      t.integer :r3, default: 0
      t.integer :r4, default: 0
      t.integer :r5, default: 0
      t.integer :total, default: 0

      t.timestamps
    end

    add_foreign_key :rating_distributions, :faculties, validate: false
    add_index :rating_distributions, :faculty_id, unique: true, algorithm: :concurrently
  end
end
