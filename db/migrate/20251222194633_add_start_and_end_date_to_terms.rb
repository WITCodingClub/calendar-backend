# frozen_string_literal: true

class AddStartAndEndDateToTerms < ActiveRecord::Migration[8.1]
  def change
    safety_assured do
      change_table :terms, bulk: true do |t|
        t.date :start_date
        t.date :end_date
      end
    end
  end
end
