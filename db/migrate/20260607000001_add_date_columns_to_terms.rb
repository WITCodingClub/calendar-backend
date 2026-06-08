class AddDateColumnsToTerms < ActiveRecord::Migration[8.1]
  def change
    add_column :terms, :start_date, :date
    add_column :terms, :end_date, :date
  end
end
