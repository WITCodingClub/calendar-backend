class CreateRelatedProfessors < ActiveRecord::Migration[8.1]
  def change
    create_table :related_professors do |t|
      t.references :faculty, null: false, foreign_key: true
      t.bigint :related_faculty_id
      t.string :rmp_id, null: false
      t.string :first_name
      t.string :last_name
      t.decimal :avg_rating, precision: 3, scale: 2
      t.timestamps
    end

    add_index :related_professors, [ :faculty_id, :rmp_id ], unique: true
    add_index :related_professors, :related_faculty_id
    add_foreign_key :related_professors, :faculties, column: :related_faculty_id
  end
end
