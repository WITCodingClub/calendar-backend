# frozen_string_literal: true

# The AP, test, and transfer credit of a student (#1020): each one names the
# WIT course it counts as. The extension sends the entries of the LeopardWeb
# Academic Transcript (source transcript), and a student can add one by hand
# (source student). DegreeProgress counts each one as a done course.
class CreateTransferCredits < ActiveRecord::Migration[8.1]
  def change
    create_table :transfer_credits do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :code, null: false
      t.string :title
      t.integer :credits
      t.string :source, null: false
      t.string :kind
      t.timestamps

      t.index [ :user_id, :code ], unique: true
    end
  end
end
