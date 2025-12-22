# frozen_string_literal: true

class AddCombinedCrnsToFinalExams < ActiveRecord::Migration[8.1]
  def change
    add_column :final_exams, :combined_crns, :text
  end

end
