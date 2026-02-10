# frozen_string_literal: true

class CreateDegreeEvaluationSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :degree_evaluation_snapshots do |t|
      t.references :user, null: false, foreign_key: true
      t.references :degree_program, null: false, foreign_key: true
      t.references :evaluation_term, null: false, foreign_key: { to_table: :terms }
      t.datetime :evaluated_at, null: false
      t.decimal :total_credits_required, precision: 5, scale: 2
      t.decimal :total_credits_completed, precision: 5, scale: 2
      t.decimal :overall_gpa, precision: 3, scale: 2
      t.decimal :minimum_gpa, precision: 3, scale: 2
      t.boolean :evaluation_met, default: false, null: false
      t.text :raw_html
      t.jsonb :parsed_data, default: {}

      t.timestamps
    end

    add_index :degree_evaluation_snapshots, [:user_id, :evaluated_at]
    add_index :degree_evaluation_snapshots, [:user_id, :degree_program_id, :evaluation_term_id], unique: true, name: "idx_degree_eval_snapshots_unique"
    add_index :degree_evaluation_snapshots, :evaluated_at
  end

end
