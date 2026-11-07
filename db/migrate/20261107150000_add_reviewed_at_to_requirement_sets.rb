# frozen_string_literal: true

# A person checks each requirement set read from a PDF against the PDF
# (#865). reviewed_at is when they did, and needs_review goes to false.
class AddReviewedAtToRequirementSets < ActiveRecord::Migration[8.1]
  def change
    add_column :requirement_sets, :reviewed_at, :datetime
  end
end
