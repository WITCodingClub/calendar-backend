class CreateRelatedProfessors < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    create_table :related_professors do |t|
      t.bigint :faculty_id, null: false
      t.string :rmp_id, null: false
      t.string :first_name
      t.string :last_name
      t.decimal :avg_rating, precision: 3, scale: 2
      t.bigint :related_faculty_id

      t.timestamps
    end

    # Add foreign keys without validation
    add_foreign_key :related_professors, :faculties, column: :faculty_id, validate: false
    add_foreign_key :related_professors, :faculties, column: :related_faculty_id, validate: false
    add_index :related_professors, [:faculty_id, :rmp_id], unique: true, algorithm: :concurrently
    add_index :related_professors, :faculty_id, algorithm: :concurrently
    add_index :related_professors, :related_faculty_id, algorithm: :concurrently
  end
end
