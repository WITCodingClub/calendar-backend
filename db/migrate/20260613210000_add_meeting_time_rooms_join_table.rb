# frozen_string_literal: true

class AddMeetingTimeRoomsJoinTable < ActiveRecord::Migration[8.0]
  def up
    create_table :course_meeting_time_rooms do |t|
      t.bigint :meeting_time_id, null: false
      t.bigint :room_id, null: false
      t.timestamps
    end

    add_index :course_meeting_time_rooms, [ :meeting_time_id, :room_id ], unique: true
    add_index :course_meeting_time_rooms, :room_id

    add_foreign_key :course_meeting_time_rooms, :course_meeting_times, column: :meeting_time_id
    add_foreign_key :course_meeting_time_rooms, :rooms

    # Migrate existing room associations to the join table
    execute <<~SQL
      INSERT INTO course_meeting_time_rooms (meeting_time_id, room_id, created_at, updated_at)
      SELECT id, room_id, NOW(), NOW()
      FROM course_meeting_times
    SQL

    remove_foreign_key :course_meeting_times, :rooms
    remove_index :course_meeting_times, :room_id
    remove_column :course_meeting_times, :room_id
  end

  def down
    add_column :course_meeting_times, :room_id, :bigint

    execute <<~SQL
      UPDATE course_meeting_times mt
      SET room_id = (
        SELECT mtr.room_id
        FROM course_meeting_time_rooms mtr
        WHERE mtr.meeting_time_id = mt.id
        ORDER BY mtr.id
        LIMIT 1
      )
    SQL

    change_column_null :course_meeting_times, :room_id, false
    add_foreign_key :course_meeting_times, :rooms
    add_index :course_meeting_times, :room_id

    drop_table :course_meeting_time_rooms
  end
end
