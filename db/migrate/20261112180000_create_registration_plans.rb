# frozen_string_literal: true

# One saved registration plan per student per term (#995): the courses and
# sections that a student picks in the schedule builder of the extension, and
# the answers of the builder. term_uid is a Banner term code. The foreign key
# to terms.uid removes a plan when its term goes away.
class CreateRegistrationPlans < ActiveRecord::Migration[8.1]
  def change
    create_table :registration_plans do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.integer :term_uid, null: false
      t.jsonb :courses, null: false, default: []
      t.jsonb :preferences, null: false, default: {}
      t.timestamps

      t.foreign_key :terms, column: :term_uid, primary_key: :uid, on_delete: :cascade
      t.index [ :user_id, :term_uid ], unique: true
      t.index :term_uid
    end
  end
end
