# frozen_string_literal: true

class CreateDegreeRequirements < ActiveRecord::Migration[8.1]
  def change
    create_table :degree_requirements do |t|
      t.references :degree_program, null: false, foreign_key: true
      t.string :area_name, null: false
      t.string :requirement_name, null: false
      t.string :requirement_type, null: false
      t.decimal :credits_required, precision: 5, scale: 2
      t.integer :courses_required
      t.references :parent_requirement, foreign_key: { to_table: :degree_requirements }
      t.text :rule_text
      t.string :subject
      t.integer :course_number
      t.string :course_choice_logic

      t.timestamps
    end

    add_index :degree_requirements, [:degree_program_id, :area_name]
    add_index :degree_requirements, :requirement_type
  end

end
