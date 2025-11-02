class CreateMeetingTimes < ActiveRecord::Migration[8.0]
  def change
    create_table :meeting_times do |t|
      t.belongs_to :course, null: false, foreign_key: true
      t.belongs_to :room, null: false, foreign_key: true

      t.integer :begin_time, null: false # ex: 0800
      t.integer :end_time, null: false # ex: 0915

      t.datetime :start_date, null: false # ex: 09/02/2025
      t.datetime :end_date, null: false # ex: 12/11/2025

      t.integer :hours_week

      t.integer :meeting_schedule_type # LEC, LAB
      t.integer :meeting_type # CLAS,

      t.integer :day_of_week # 0=sunday, 1=monday, ..., 6=saturday

      t.timestamps
    end

    add_index :meeting_times, :day_of_week
  end
end