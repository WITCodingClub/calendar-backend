# frozen_string_literal: true

# Data that the extension collects from Brightspace and sends to
# POST /api/brightspace/sync. Every row hangs off one connection, and a
# connection belongs to one user, so imported data is never shared between
# users. Imported rows are never deleted by a sync: a row that a complete
# section no longer lists gets removed_at.
class CreateBrightspaceTables < ActiveRecord::Migration[8.1]
  def change
    create_table :brightspace_connections do |t|
      t.references :user, null: false, foreign_key: true
      t.string :host, null: false
      t.string :learner_id, null: false
      t.string :status, null: false, default: "active"
      t.datetime :connected_at, null: false
      t.datetime :disconnected_at
      t.datetime :last_synced_at
      t.datetime :reconnect_required_at
      t.timestamps
    end
    add_index :brightspace_connections, [ :user_id, :host, :learner_id ], unique: true,
              name: "index_brightspace_connections_on_identity"
    add_index :brightspace_connections, :user_id, unique: true, where: "status = 'active'",
              name: "index_brightspace_connections_one_active_per_user"

    create_table :brightspace_syncs do |t|
      t.references :connection, null: false, foreign_key: { to_table: :brightspace_connections }
      t.string :snapshot_id, null: false
      t.string :payload_digest, null: false
      t.datetime :collected_at, null: false
      t.string :status, null: false
      t.jsonb :result, null: false, default: {}
      t.timestamps
    end
    add_index :brightspace_syncs, [ :connection_id, :snapshot_id ], unique: true

    create_table :brightspace_course_offerings do |t|
      t.references :connection, null: false, foreign_key: { to_table: :brightspace_connections }
      # Both nullable: a class can be stored before it maps to a registration
      # course. A mapped course sets the term.
      t.references :course, foreign_key: true
      t.references :term, foreign_key: true
      t.string :source_id, null: false
      t.string :title, null: false
      t.integer :data_version, null: false, default: 1
      # { "assignments" => { "collected_at" => ..., "succeeded_at" => ..., "error" => ... } }
      t.jsonb :sections, null: false, default: {}
      # { "points_earned", "points_possible", "percent", "letter" } from the gradebook.
      t.jsonb :reported_total
      t.timestamps
    end
    add_index :brightspace_course_offerings, [ :connection_id, :source_id ], unique: true

    create_table :brightspace_assignments do |t|
      t.references :course_offering, null: false, foreign_key: { to_table: :brightspace_course_offerings }
      t.string :kind, null: false
      t.string :source_id, null: false
      t.string :title, null: false
      t.text :description
      t.string :source_url
      # Class-wide dates, as Brightspace shows them to the class.
      t.datetime :due_at
      t.datetime :opens_at
      t.datetime :closes_at
      # This student's own state: an individual deadline (special access),
      # the submission, and feedback.
      t.datetime :user_due_at
      t.string :submission_status
      t.datetime :submitted_at
      t.text :feedback
      t.datetime :removed_at
      t.timestamps
    end
    add_index :brightspace_assignments, [ :course_offering_id, :kind, :source_id ], unique: true,
              name: "index_brightspace_assignments_on_source"

    create_table :brightspace_announcements do |t|
      t.references :course_offering, null: false, foreign_key: { to_table: :brightspace_course_offerings }
      t.string :source_id, null: false
      t.string :title, null: false
      t.text :body
      t.string :source_url
      t.datetime :posted_at
      t.datetime :removed_at
      t.timestamps
    end
    add_index :brightspace_announcements, [ :course_offering_id, :source_id ], unique: true,
              name: "index_brightspace_announcements_on_source"

    create_table :brightspace_grade_categories do |t|
      t.references :course_offering, null: false, foreign_key: { to_table: :brightspace_course_offerings }
      t.string :source_id, null: false
      t.string :name, null: false
      t.decimal :weight, precision: 8, scale: 4
      t.integer :drop_lowest
      t.integer :drop_highest
      t.boolean :extra_credit
      t.datetime :removed_at
      t.timestamps
    end
    add_index :brightspace_grade_categories, [ :course_offering_id, :source_id ], unique: true,
              name: "index_brightspace_grade_categories_on_source"

    create_table :brightspace_grade_items do |t|
      t.references :course_offering, null: false, foreign_key: { to_table: :brightspace_course_offerings }
      t.references :grade_category, foreign_key: { to_table: :brightspace_grade_categories }
      t.references :assignment, foreign_key: { to_table: :brightspace_assignments }
      t.string :source_id, null: false
      t.string :name, null: false
      t.decimal :points_earned, precision: 10, scale: 4
      t.decimal :points_possible, precision: 10, scale: 4
      t.decimal :weight, precision: 8, scale: 4
      t.string :grading_status, null: false
      t.boolean :extra_credit
      t.text :feedback
      t.datetime :graded_at
      t.datetime :removed_at
      t.timestamps
    end
    add_index :brightspace_grade_items, [ :course_offering_id, :source_id ], unique: true,
              name: "index_brightspace_grade_items_on_source"

    create_table :brightspace_syllabi do |t|
      t.references :course_offering, null: false, foreign_key: { to_table: :brightspace_course_offerings },
                                      index: { unique: true }
      t.string :source_id
      t.string :source_url
      t.string :title
      t.string :revision, null: false
      t.jsonb :extracted, null: false, default: {}
      t.datetime :removed_at
      t.timestamps
    end
  end
end
