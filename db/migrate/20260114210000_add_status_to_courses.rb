# frozen_string_literal: true

class AddStatusToCourses < ActiveRecord::Migration[7.1]
  def change
    add_column :courses, :status, :string, default: 'active', null: false
    add_index :courses, :status
  end
end
