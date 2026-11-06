# frozen_string_literal: true

# A requirement set read from a PDF catalog needs a person to check it (#865).
# reviewed_at is when they did. review_notes holds the checks that failed
# during the import, such as a printed total that does not match its rows.
class AddReviewFieldsToRequirementSets < ActiveRecord::Migration[8.1]
  def change
    add_column :requirement_sets, :reviewed_at, :datetime
    add_column :requirement_sets, :review_notes, :text
  end
end
