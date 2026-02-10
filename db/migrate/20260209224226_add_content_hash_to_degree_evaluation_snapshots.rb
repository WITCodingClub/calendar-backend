# frozen_string_literal: true

class AddContentHashToDegreeEvaluationSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :degree_evaluation_snapshots, :content_hash, :string
    add_index :degree_evaluation_snapshots, :content_hash
  end

end
