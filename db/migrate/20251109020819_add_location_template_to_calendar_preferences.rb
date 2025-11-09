class AddLocationTemplateToCalendarPreferences < ActiveRecord::Migration[8.1]
  def change
    add_column :calendar_preferences, :location_template, :text
  end
end
