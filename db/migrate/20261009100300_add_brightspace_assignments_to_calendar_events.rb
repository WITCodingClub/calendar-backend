# frozen_string_literal: true

# Brightspace deadlines become calendar events, keyed on the assignment, so a
# changed deadline updates the event instead of adding one. Deadline changes
# are recorded for notifications.
class AddBrightspaceAssignmentsToCalendarEvents < ActiveRecord::Migration[8.1]
  def change
    add_reference :calendar_events, :brightspace_assignment, foreign_key: { to_table: :brightspace_assignments }
    add_index :calendar_events, [ :calendar_id, :brightspace_assignment_id ], unique: true,
              where: "brightspace_assignment_id IS NOT NULL", name: "idx_calendar_events_unique_brightspace_assignment"

    create_table :brightspace_deadline_changes do |t|
      t.references :assignment, null: false, foreign_key: { to_table: :brightspace_assignments }
      t.string :field, null: false
      t.datetime :previous_at
      t.datetime :current_at
      t.datetime :detected_at, null: false
      t.datetime :notified_at
      t.timestamps
    end
    add_index :brightspace_deadline_changes, :notified_at, where: "notified_at IS NULL",
              name: "index_brightspace_deadline_changes_unnotified"
  end
end
