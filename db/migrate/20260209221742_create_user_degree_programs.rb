# frozen_string_literal: true

class CreateUserDegreePrograms < ActiveRecord::Migration[8.1]
  def change
    create_table :user_degree_programs do |t|
      t.references :user, null: false, foreign_key: true
      t.references :degree_program, null: false, foreign_key: true
      t.string :leopardweb_program_id
      t.string :program_type, null: false
      t.integer :catalog_year, null: false
      t.datetime :declared_at
      t.string :status, default: "active", null: false
      t.boolean :primary, default: false, null: false
      t.date :completion_date

      t.timestamps
    end

    add_index :user_degree_programs, [:user_id, :degree_program_id], unique: true
    add_index :user_degree_programs, [:user_id, :primary], unique: true, where: '"primary" = true'
    add_index :user_degree_programs, :status
  end

end
