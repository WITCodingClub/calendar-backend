# frozen_string_literal: true

class AddUniversityEventsSettingsToUserExtensionConfigs < ActiveRecord::Migration[8.1]
  def change
    add_column :user_extension_configs, :sync_university_events, :boolean, default: false, null: false
    add_column :user_extension_configs, :university_event_categories, :jsonb, default: []
  end
end
