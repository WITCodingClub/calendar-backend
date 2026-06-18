class CreateCourses < ActiveRecord::Migration[8.0]
  def change
    create_table :courses do |t|
      t.belongs_to :term, null: false, foreign_key: true
      t.integer :crn, null: false
      t.string :section_number, null: false
      t.string :subject, null: false # ex: Computer Science (COMP)
      t.integer :course_number, null: false # ex: 1000
      t.string :title, null: false
      t.integer :credit_hours
      t.string :grade_mode

      t.date :start_date, null: false
      t.date :end_date, null: false

      t.string  :schedule_type,   null: false
      t.string  :status,          null: false, default: "active"
      t.integer :seats_available
      t.integer :seats_capacity

      t.timestamps
    end

    add_index :courses, [ :crn, :term_id ], unique: true

    add_index :courses, :status

    # ----- Check constraints to mirror model rules / sanity -----

    # credit hours must be positive if present
    add_check_constraint :courses,
                         "credit_hours IS NULL OR credit_hours > 0",
                         name: "courses_credit_hours_positive"

    # dates: end on/after start when both present
    add_check_constraint :courses,
                         "start_date IS NULL OR end_date IS NULL OR end_date >= start_date",
                         name: "courses_end_date_on_or_after_start_date"

    # seats: non‑negative, and available <= capacity when both present
    add_check_constraint :courses,
                         "seats_available IS NULL OR seats_available >= 0",
                         name: "courses_seats_available_non_negative"

    add_check_constraint :courses,
                         "seats_capacity IS NULL OR seats_capacity >= 0",
                         name: "courses_seats_capacity_non_negative"

    add_check_constraint :courses,
                         "seats_available IS NULL OR seats_capacity IS NULL OR seats_available <= seats_capacity",
                         name: "courses_seats_available_le_capacity"

    # status enum: active / cancelled
    add_check_constraint :courses,
                         "status IN ('active', 'cancelled')",
                         name: "courses_status_valid"

    # schedule_type enum values
    add_check_constraint :courses,
                         "schedule_type IN ('EXT','HYB','IND','LAB','LEC','ONL','ONB','OLB','OLC','RLB','RLC','SAB')",
                         name: "courses_schedule_type_valid"
  end
end
