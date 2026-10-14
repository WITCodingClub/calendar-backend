# frozen_string_literal: true

# A finals schedule is term data that every student's calendar uses. When the
# admin who uploaded it is deleted, the schedule stays and loses its uploader.
class AllowNullUploadedByOnFinalsSchedules < ActiveRecord::Migration[8.1]
  def change
    change_column_null :finals_schedules, :uploaded_by_id, true
  end
end
