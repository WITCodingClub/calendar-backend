# frozen_string_literal: true

class CreateTerms < ActiveRecord::Migration[8.1]
  def change
    create_table :terms do |t|
      t.integer :uid,    null: false
      t.integer :year,   null: false   # 2012+
      t.integer :season, null: false   # 1 = spring, 2 = fall, 3 = summer

      t.timestamps
    end

    # Each (year, season) is a single term
    add_index :terms, [:year, :season], unique: true

    # Each uid points to exactly one term
    add_index :terms, :uid, unique: true

    # Keep DB in sync with enum :season mapping
    add_check_constraint :terms,
                         "season IN (1, 2, 3)",
                         name: "terms_season_valid"

    # First real term is Fall 2012; anything from 2012 onward is allowed
    add_check_constraint :terms,
                         "year >= 2012",
                         name: "terms_year_not_before_first_term"
  end
end
