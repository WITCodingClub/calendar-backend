class AddLocationTemplateToEventPreferences < ActiveRecord::Migration[8.1]
  def change
    add_column :event_preferences, :location_template, :text
  end
end
