# frozen_string_literal: true

# Data that the user owns, kept apart from imported Brightspace data. A sync
# never writes these tables.
class CreateBrightspacePreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :brightspace_assignment_preferences do |t|
      t.references :user, null: false, foreign_key: true
      t.references :assignment, null: false, foreign_key: { to_table: :brightspace_assignments }, index: { unique: true }
      t.string :progress, null: false, default: "not_started"
      t.datetime :due_at_override
      t.timestamps
    end

    create_table :brightspace_class_preferences do |t|
      t.references :user, null: false, foreign_key: true
      t.references :course_offering, null: false, foreign_key: { to_table: :brightspace_course_offerings },
                                      index: { unique: true }
      # Calendar settings. A nil column inherits the default.
      t.boolean :sync_enabled
      t.string :included_kinds, array: true
      t.text :title_template
      t.text :description_template
      t.text :location_template
      t.string :color_id
      t.string :visibility
      t.jsonb :reminder_settings
      # Grade settings.
      t.string :grade_mode
      t.jsonb :grade_categories
      t.timestamps
    end
  end
end
