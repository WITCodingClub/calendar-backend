# frozen_string_literal: true

# Banner's waitlist for a section: its size and the places still open. A full
# section with an open waitlist place can still be joined.
class AddWaitlistCountsToCourses < ActiveRecord::Migration[8.1]
  def change
    add_column :courses, :waitlist_capacity, :integer
    add_column :courses, :waitlist_available, :integer
  end
end
