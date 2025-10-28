class CreateMeetingTimes < ActiveRecord::Migration[8.0]
  def change
    create_table :meeting_times do |t|
      t.belongs_to :courses, null: false, foreign_key: true
      t.belongs_to :room, null: false, foreign_key: true

      t.integer :begin_time, null: false # ex: 0800
      t.integer :end_time, null: false # ex: 0915

      t.datetime :start_date, null: false # ex: 09/02/2025
      t.datetime :end_date, null: false # ex: 12/11/2025

      t.integer :hours_week

      t.integer :meeting_schedule_type # LEC, LAB
      t.integer :meeting_typee # CLAS,

      t.boolean :monday
      t.boolean :tuesday
      t.boolean :wednesday
      t.boolean :thursday
      t.boolean :friday
      t.boolean :saturday
      t.boolean :sunday

      t.timestamps
    end
  end
end