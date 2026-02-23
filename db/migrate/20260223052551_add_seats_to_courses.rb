# frozen_string_literal: true

class AddSeatsToCourses < ActiveRecord::Migration[8.1]
  def change
    add_column :courses, :seats_available, :integer
    add_column :courses, :seats_capacity, :integer
  end

end
