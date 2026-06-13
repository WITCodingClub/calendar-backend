class CourseMeetingTimes < ActiveRecord::Migration[8.1]
  def change
    create_table :course_meeting_times do |t|
      t.belongs_to :course, null: false, foreign_key: true
      t.belongs_to :room,   null: false, foreign_key: true

      # Times in HHMM format, e.g. 800, 915
      t.integer :begin_time, null: false
      t.integer :end_time,   null: false

      # Datetimes from Banner; stored as full timestamps
      t.datetime :start_date, null: false
      t.datetime :end_date,   null: false

      t.integer :hours_week

      t.integer :meeting_schedule_type, null: false   # enum: lecture(1), laboratory(2)
      t.integer :meeting_type,          null: false   # enum: class_meeting(1)
      t.integer :day_of_week,           null: false   # enum 0..6

      t.timestamps
    end

    add_index :course_meeting_times, :day_of_week

    # --- Check constraints to enforce basic invariants ---

    # day_of_week enum 0..6
    add_check_constraint :course_meeting_times,
                         "day_of_week BETWEEN 0 AND 6",
                         name: "course_meeting_times_day_of_week_range"

    # meeting_schedule_type enum: lecture(1), laboratory(2)
    add_check_constraint :course_meeting_times,
                         "meeting_schedule_type IN (1, 2)",
                         name: "course_meeting_times_schedule_type_valid"

    # meeting_type enum: class_meeting(1)
    add_check_constraint :course_meeting_times,
                         "meeting_type IN (1)",
                         name: "course_meeting_times_meeting_type_valid"

    # times: 0–2359, and end >= begin
    add_check_constraint :course_meeting_times,
                         "begin_time BETWEEN 0 AND 2359",
                         name: "course_meeting_times_begin_time_range"

    add_check_constraint :course_meeting_times,
                         "end_time BETWEEN 0 AND 2359",
                         name: "course_meeting_times_end_time_range"

    add_check_constraint :course_meeting_times,
                         "end_time >= begin_time",
                         name: "course_meeting_times_end_after_begin"

    # dates: end on/after start
    add_check_constraint :course_meeting_times,
                         "end_date >= start_date",
                         name: "course_meeting_times_end_date_on_or_after_start_date"
  end
end
