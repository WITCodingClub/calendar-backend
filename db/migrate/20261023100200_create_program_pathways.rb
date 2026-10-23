# frozen_string_literal: true

# Paths through more than one program: the 3+1 and 4+1 master's degrees
# (Double Leopard) and the 5-year B.S. plus M.Arch (#526). A step names a
# program and a plan length, not a catalog year, because each program a
# student takes has its own catalog year.
class CreateProgramPathways < ActiveRecord::Migration[8.1]
  def change
    create_table :program_pathways do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.string :kind, null: false
      t.integer :max_shared_courses
      t.integer :max_shared_credits
      t.boolean :active, null: false, default: true
      t.timestamps
      t.index :slug, unique: true
    end

    create_table :program_pathway_steps do |t|
      t.references :program_pathway, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :degree_program, null: false, foreign_key: true
      t.integer :position, null: false
      t.integer :plan_years
      t.timestamps
      t.index [ :program_pathway_id, :position ], unique: true
    end
  end
end
