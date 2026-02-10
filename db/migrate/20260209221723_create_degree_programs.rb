# frozen_string_literal: true

class CreateDegreePrograms < ActiveRecord::Migration[8.1]
  def change
    create_table :degree_programs do |t|
      t.string :program_code, null: false
      t.string :leopardweb_code, null: false
      t.string :program_name, null: false
      t.string :degree_type, null: false
      t.string :level, null: false
      t.string :college
      t.string :department
      t.integer :catalog_year, null: false
      t.decimal :credit_hours_required, precision: 5, scale: 2
      t.decimal :minimum_gpa, precision: 3, scale: 2
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :degree_programs, :program_code, unique: true
    add_index :degree_programs, :leopardweb_code, unique: true
    add_index :degree_programs, [:catalog_year, :program_code]
    add_index :degree_programs, :active
  end

end
